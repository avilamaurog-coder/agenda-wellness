-- =============================================================================
-- Agenda Wellness · Migración 0002 · Funciones auxiliares y triggers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helpers de seguridad (SECURITY DEFINER para evitar recursión en RLS)
-- -----------------------------------------------------------------------------
create or replace function public.current_profile()
returns public.profiles
language sql stable security definer set search_path = public
as $$
  select * from public.profiles where id = auth.uid() and is_active
$$;

create or replace function public.current_center_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select center_id from public.profiles where id = auth.uid() and is_active
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and is_active
$$;

create or replace function public.has_role(roles public.user_role[])
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select role = any(roles) from public.profiles where id = auth.uid() and is_active), false)
$$;

create or replace function public.is_admin()
returns boolean language sql stable as $$ select public.has_role(array['admin']::public.user_role[]) $$;

create or replace function public.is_front_desk()
returns boolean language sql stable as $$ select public.has_role(array['admin','receptionist']::public.user_role[]) $$;

-- ¿El profesional actual atendió (o tiene asignado) a este cliente?
create or replace function public.therapist_has_client(p_client_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.appointments
    where client_id = p_client_id and therapist_id = auth.uid()
  )
$$;

-- -----------------------------------------------------------------------------
-- updated_at automático
-- -----------------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['centers','profiles','clients','services','combos','appointments','clinical_records'] loop
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Alta de usuario → perfil
--   * El primer usuario del sistema crea el centro y queda como admin.
--   * El resto queda INACTIVO como 'therapist' hasta que un admin lo habilite
--     (el rol nunca se toma de raw_user_meta_data: lo controla el cliente).
--   * Usuarios invitados por un admin vía Edge Function `invite-user`
--     traen app_metadata.role y app_metadata.center_id (solo escribible con service_role).
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_center uuid;
  v_role   public.user_role;
  v_active boolean;
begin
  if (new.raw_app_meta_data ? 'center_id') then
    v_center := (new.raw_app_meta_data->>'center_id')::uuid;
    v_role   := coalesce((new.raw_app_meta_data->>'role')::public.user_role, 'therapist');
    v_active := true;
  elsif not exists (select 1 from public.profiles) then
    select id into v_center from public.centers order by created_at limit 1;
    if v_center is null then
      insert into public.centers(name) values ('Mi Centro Wellness') returning id into v_center;
    end if;
    v_role := 'admin';
    v_active := true;
  else
    select id into v_center from public.centers order by created_at limit 1;
    v_role := 'therapist';
    v_active := false;
  end if;

  insert into public.profiles(id, center_id, full_name, email, phone, role, is_active)
  values (
    new.id, v_center,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data->>'phone',
    v_role, v_active
  );

  if not v_active then
    insert into public.internal_notifications(center_id, kind, title, body, payload)
    values (v_center, 'system', 'Nuevo usuario pendiente de aprobación',
            coalesce(new.raw_user_meta_data->>'full_name', new.email),
            jsonb_build_object('user_id', new.id));
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Un usuario no-admin no puede cambiarse rol, centro ni estado
create or replace function public.tg_protect_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;            -- service_role / sistema
  if public.is_admin() then
    if old.id = auth.uid() and (new.role <> 'admin' or not new.is_active) then
      raise exception 'Un administrador no puede quitarse su propio rol ni desactivarse';
    end if;
    return new;
  end if;
  if new.role is distinct from old.role
     or new.center_id is distinct from old.center_id
     or new.is_active is distinct from old.is_active then
    raise exception 'Permiso denegado: solo un administrador puede modificar rol, centro o estado';
  end if;
  return new;
end $$;

create trigger protect_profile before update on public.profiles
  for each row execute function public.tg_protect_profile();

-- -----------------------------------------------------------------------------
-- Historial de precios
-- -----------------------------------------------------------------------------
create or replace function public.tg_service_price_history()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.service_price_history(service_id, old_price, new_price, old_promo_price, new_promo_price, changed_by)
    values (new.id, null, new.price, null, new.promo_price, auth.uid());
  elsif new.price is distinct from old.price or new.promo_price is distinct from old.promo_price then
    insert into public.service_price_history(service_id, old_price, new_price, old_promo_price, new_promo_price, changed_by)
    values (new.id, old.price, new.price, old.promo_price, new.promo_price, auth.uid());
  end if;
  return new;
end $$;

create trigger service_price_history
  after insert or update of price, promo_price on public.services
  for each row execute function public.tg_service_price_history();

-- -----------------------------------------------------------------------------
-- Turnos: defaults, validación y bitácora
-- -----------------------------------------------------------------------------
create or replace function public.tg_appointment_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_service public.services;
  v_combo   public.combos;
  v_minutes int;
begin
  -- Centro por defecto
  if new.center_id is null then new.center_id := public.current_center_id(); end if;

  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());

    -- Precio y duración por defecto desde servicio o combo
    if new.service_id is not null then
      select * into v_service from public.services where id = new.service_id;
      if not found or not v_service.is_active then
        raise exception 'El servicio no existe o está inactivo';
      end if;
      v_minutes := v_service.duration_minutes;
      if new.price = 0 then
        new.price := case
          when v_service.promo_price is not null
               and (v_service.promo_valid_until is null or v_service.promo_valid_until >= current_date)
          then v_service.promo_price else v_service.price end;
      end if;
    else
      select * into v_combo from public.combos where id = new.combo_id;
      if not found or not v_combo.is_active then
        raise exception 'El combo no existe o está inactivo';
      end if;
      select coalesce(sum(s.duration_minutes), 60) into v_minutes
      from public.combo_items ci join public.services s on s.id = ci.service_id
      where ci.combo_id = new.combo_id;
      if new.price = 0 then new.price := v_combo.price; end if;
    end if;

    if new.ends_at is null or new.ends_at <= new.starts_at then
      new.ends_at := new.starts_at + make_interval(mins => v_minutes);
    end if;
  end if;

  -- Validar que el profesional pertenezca al centro y esté activo
  if not exists (select 1 from public.profiles
                 where id = new.therapist_id and center_id = new.center_id and is_active) then
    raise exception 'Profesional inválido para este centro';
  end if;

  -- Bloqueos de agenda
  if new.status in ('pending','confirmed') and exists (
    select 1 from public.schedule_blocks b
    where b.center_id = new.center_id
      and (b.therapist_id is null or b.therapist_id = new.therapist_id)
      and tstzrange(b.starts_at, b.ends_at) && tstzrange(new.starts_at, new.ends_at)
  ) then
    raise exception 'El horario está bloqueado en la agenda';
  end if;

  -- Timestamps de transición de estado
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    case new.status
      when 'confirmed' then new.confirmed_at := now();
      when 'completed' then new.completed_at := now();
      when 'cancelled' then
        new.cancelled_at := now();
        new.cancelled_by := coalesce(new.cancelled_by, auth.uid());
      else null;
    end case;
  end if;

  if tg_op = 'UPDATE' and new.starts_at is distinct from old.starts_at then
    new.reschedule_count := old.reschedule_count + 1;
  end if;

  return new;
end $$;

create trigger appointment_before
  before insert or update on public.appointments
  for each row execute function public.tg_appointment_before();

create or replace function public.tg_appointment_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_event public.appointment_event;
  v_client text;
begin
  if tg_op = 'INSERT' then
    insert into public.appointment_events(appointment_id, event, new_starts_at, new_status, performed_by)
    values (new.id, 'created', new.starts_at, new.status, auth.uid());
    perform public.schedule_reminders(new.id);
    return new;
  end if;

  if new.starts_at is distinct from old.starts_at or new.therapist_id is distinct from old.therapist_id then
    insert into public.appointment_events(appointment_id, event, old_starts_at, new_starts_at, reason, performed_by)
    values (new.id, 'rescheduled', old.starts_at, new.starts_at,
            nullif(current_setting('app.reason', true), ''), auth.uid());
    perform public.schedule_reminders(new.id);
  end if;

  if new.status is distinct from old.status then
    v_event := case new.status
      when 'confirmed' then 'confirmed'
      when 'completed' then 'completed'
      when 'cancelled' then 'cancelled'
      when 'no_show'   then 'no_show'
      else 'updated' end;
    insert into public.appointment_events(appointment_id, event, old_status, new_status, reason, performed_by)
    values (new.id, v_event, old.status, new.status, new.cancellation_reason, auth.uid());

    if new.status in ('cancelled','no_show','completed') then
      update public.appointment_reminders set status = 'skipped'
      where appointment_id = new.id and status = 'scheduled';
    end if;

    if new.status = 'cancelled' then
      select first_name || ' ' || last_name into v_client from public.clients where id = new.client_id;
      insert into public.internal_notifications(center_id, user_id, kind, title, body, payload)
      values (new.center_id, new.therapist_id, 'cancellation', 'Turno cancelado',
              v_client || ' · ' || to_char(new.starts_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI'),
              jsonb_build_object('appointment_id', new.id));
    end if;
  end if;
  return new;
end $$;

create trigger appointment_after
  after insert or update on public.appointments
  for each row execute function public.tg_appointment_after();

-- -----------------------------------------------------------------------------
-- Programación de recordatorios (48 / 24 / 2 h)
-- -----------------------------------------------------------------------------
create or replace function public.schedule_reminders(p_appointment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  a public.appointments;
  c public.clients;
  h int;
  ch public.notification_channel;
begin
  select * into a from public.appointments where id = p_appointment_id;
  select * into c from public.clients where id = a.client_id;

  delete from public.appointment_reminders
  where appointment_id = a.id and status = 'scheduled';

  if a.status not in ('pending','confirmed') or not c.accepts_reminders then
    return;
  end if;

  foreach h in array array[48, 24, 2] loop
    for ch in
      select t.channel from public.message_templates t
      where t.center_id = a.center_id and t.hours_before = h and t.is_active
        and (
          (t.channel = 'whatsapp' and coalesce(c.whatsapp, c.phone) is not null) or
          (t.channel = 'email'    and c.email is not null) or
          (t.channel = 'push')
        )
    loop
      if a.starts_at - make_interval(hours => h) > now() then
        insert into public.appointment_reminders(appointment_id, channel, hours_before, scheduled_for)
        values (a.id, ch, h, a.starts_at - make_interval(hours => h))
        on conflict (appointment_id, channel, hours_before)
        do update set scheduled_for = excluded.scheduled_for, status = 'scheduled', attempts = 0, error = null;
      end if;
    end loop;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Notificación interna por cliente nuevo
-- -----------------------------------------------------------------------------
create or replace function public.tg_client_created()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_by := coalesce(new.created_by, auth.uid());
  if new.center_id is null then new.center_id := public.current_center_id(); end if;
  return new;
end $$;

create trigger client_before_insert before insert on public.clients
  for each row execute function public.tg_client_created();

create or replace function public.tg_client_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.internal_notifications(center_id, kind, title, body, payload)
  values (new.center_id, 'new_client', 'Cliente nuevo', new.first_name || ' ' || new.last_name,
          jsonb_build_object('client_id', new.id));
  return new;
end $$;

create trigger client_after_insert after insert on public.clients
  for each row execute function public.tg_client_notify();

-- center_id por defecto para el resto de tablas de negocio
create or replace function public.tg_default_center()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.center_id is null then new.center_id := public.current_center_id(); end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['services','service_categories','combos','promotions','payments','message_templates','schedule_blocks'] loop
    execute format('create trigger default_center before insert on public.%I
                    for each row execute function public.tg_default_center()', t);
  end loop;
end $$;

create or replace function public.tg_payment_defaults()
returns trigger language plpgsql as $$
begin
  new.registered_by := coalesce(new.registered_by, auth.uid());
  if new.client_id is null and new.appointment_id is not null then
    select client_id into new.client_id from public.appointments where id = new.appointment_id;
  end if;
  return new;
end $$;

create trigger payment_defaults before insert on public.payments
  for each row execute function public.tg_payment_defaults();

-- -----------------------------------------------------------------------------
-- Auditoría de tablas sensibles
-- -----------------------------------------------------------------------------
create or replace function public.tg_audit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log(table_name, record_id, action, old_data, new_data, user_id)
  values (
    tg_table_name,
    coalesce((case when tg_op = 'DELETE' then old.id else new.id end), null),
    tg_op,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['clients','payments','clinical_records','profiles','services'] loop
    execute format('create trigger audit after insert or update or delete on public.%I
                    for each row execute function public.tg_audit()', t);
  end loop;
end $$;
