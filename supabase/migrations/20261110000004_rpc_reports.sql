-- =============================================================================
-- Agenda Wellness · Migración 0004 · RPCs de negocio, dashboard y reportes
-- Todas las RPC son SECURITY INVOKER (respetan RLS) salvo indicación.
-- Se exponen vía PostgREST:  POST /rest/v1/rpc/<nombre>
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Restricción: un profesional solo puede cambiar estado y notas de sus turnos
-- -----------------------------------------------------------------------------
create or replace function public.tg_appointment_therapist_guard()
returns trigger language plpgsql as $$
begin
  if auth.uid() is null or public.is_front_desk() then return new; end if;
  if new.client_id    is distinct from old.client_id
  or new.therapist_id is distinct from old.therapist_id
  or new.service_id   is distinct from old.service_id
  or new.combo_id     is distinct from old.combo_id
  or new.starts_at    is distinct from old.starts_at
  or new.ends_at      is distinct from old.ends_at
  or new.price        is distinct from old.price
  or new.discount_amount is distinct from old.discount_amount then
    raise exception 'Un profesional solo puede actualizar el estado y las notas de sus turnos';
  end if;
  if new.status = 'cancelled' then
    raise exception 'Las cancelaciones las registra recepción o administración';
  end if;
  return new;
end $$;

create trigger appointment_therapist_guard before update on public.appointments
  for each row execute function public.tg_appointment_therapist_guard();

-- -----------------------------------------------------------------------------
-- Cancelar turno
-- -----------------------------------------------------------------------------
create or replace function public.cancel_appointment(p_id uuid, p_reason text)
returns public.appointments
language plpgsql security invoker set search_path = public as $$
declare r public.appointments;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'El motivo de cancelación es obligatorio';
  end if;
  update public.appointments
     set status = 'cancelled', cancellation_reason = p_reason, cancelled_by = auth.uid()
   where id = p_id and status in ('pending','confirmed')
  returning * into r;
  if r.id is null then raise exception 'Turno inexistente o no cancelable'; end if;
  return r;
end $$;

-- -----------------------------------------------------------------------------
-- Reprogramar turno (mantiene el mismo registro, deja bitácora con motivo)
-- -----------------------------------------------------------------------------
create or replace function public.reschedule_appointment(
  p_id uuid,
  p_new_start timestamptz,
  p_new_therapist uuid default null,
  p_reason text default null
) returns public.appointments
language plpgsql security invoker set search_path = public as $$
declare
  r public.appointments;
  v_duration interval;
begin
  select ends_at - starts_at into v_duration from public.appointments where id = p_id;
  if v_duration is null then raise exception 'Turno inexistente'; end if;

  perform set_config('app.reason', coalesce(p_reason, ''), true);

  update public.appointments
     set starts_at    = p_new_start,
         ends_at      = p_new_start + v_duration,
         therapist_id = coalesce(p_new_therapist, therapist_id),
         status       = case when status = 'confirmed' then 'pending' else status end
   where id = p_id and status in ('pending','confirmed')
  returning * into r;

  if r.id is null then raise exception 'Turno no reprogramable en su estado actual'; end if;
  return r;
exception
  when exclusion_violation then
    raise exception 'El profesional ya tiene un turno en ese horario' using errcode = 'P0409';
end $$;

-- -----------------------------------------------------------------------------
-- Cambio de estado genérico (confirmar / completar / ausente)
-- -----------------------------------------------------------------------------
create or replace function public.set_appointment_status(p_id uuid, p_status public.appointment_status)
returns public.appointments
language plpgsql security invoker set search_path = public as $$
declare r public.appointments; cur public.appointment_status;
begin
  select status into cur from public.appointments where id = p_id;
  if cur is null then raise exception 'Turno inexistente'; end if;

  -- Máquina de estados
  if not (
    (cur = 'pending'   and p_status in ('confirmed','completed','no_show')) or
    (cur = 'confirmed' and p_status in ('pending','completed','no_show'))   or
    (cur = 'no_show'   and p_status = 'completed')
  ) then
    raise exception 'Transición inválida: % → %', cur, p_status;
  end if;
  if p_status = 'cancelled' then
    raise exception 'Use cancel_appointment para cancelar';
  end if;

  update public.appointments set status = p_status where id = p_id returning * into r;
  return r;
end $$;

-- -----------------------------------------------------------------------------
-- Horarios disponibles para un servicio en un día
-- Devuelve slots libres considerando horario laboral, turnos y bloqueos.
-- -----------------------------------------------------------------------------
create or replace function public.available_slots(
  p_date date,
  p_service_id uuid,
  p_therapist_id uuid default null
) returns table (therapist_id uuid, therapist_name text, slot_start timestamptz, slot_end timestamptz)
language sql stable security definer set search_path = public as $$
  with cfg as (
    select c.id center_id, c.timezone tz, c.slot_minutes
    from public.centers c where c.id = public.current_center_id()
  ),
  svc as (
    select s.id, s.duration_minutes + s.buffer_minutes as minutes
    from public.services s, cfg
    where s.id = p_service_id and s.center_id = cfg.center_id and s.is_active
  ),
  therapists as (
    select p.id, p.full_name
    from public.profiles p
    join cfg on p.center_id = cfg.center_id
    where p.is_active and p.role in ('therapist','admin')
      and (p_therapist_id is null or p.id = p_therapist_id)
      and (not exists (select 1 from public.service_therapists st where st.service_id = p_service_id)
           or exists (select 1 from public.service_therapists st where st.service_id = p_service_id and st.therapist_id = p.id))
  ),
  windows as (
    select t.id, t.full_name,
           ((p_date + ts.start_time) at time zone cfg.tz) as w_start,
           ((p_date + ts.end_time)   at time zone cfg.tz) as w_end
    from therapists t
    join public.therapist_schedules ts on ts.therapist_id = t.id and ts.weekday = extract(dow from p_date)
    cross join cfg
  ),
  candidates as (
    select w.id, w.full_name, gs as s_start, gs + make_interval(mins => svc.minutes) as s_end
    from windows w
    cross join svc
    cross join cfg
    cross join lateral generate_series(w.w_start, w.w_end - make_interval(mins => svc.minutes),
                                       make_interval(mins => cfg.slot_minutes)) gs
  )
  select c.id, c.full_name, c.s_start, c.s_end
  from candidates c, cfg
  where c.s_start > now()
    and not exists (
      select 1 from public.appointments a
      where a.therapist_id = c.id and a.status in ('pending','confirmed')
        and tstzrange(a.starts_at, a.ends_at) && tstzrange(c.s_start, c.s_end))
    and not exists (
      select 1 from public.schedule_blocks b
      where b.center_id = cfg.center_id and (b.therapist_id is null or b.therapist_id = c.id)
        and tstzrange(b.starts_at, b.ends_at) && tstzrange(c.s_start, c.s_end))
  order by c.s_start, c.full_name
$$;

-- -----------------------------------------------------------------------------
-- Reprogramación automática: sugiere los próximos N huecos para un turno cancelado
-- -----------------------------------------------------------------------------
create or replace function public.suggest_reschedule(p_appointment_id uuid, p_days int default 7, p_limit int default 6)
returns table (therapist_id uuid, therapist_name text, slot_start timestamptz, slot_end timestamptz)
language plpgsql stable security invoker set search_path = public as $$
declare a public.appointments; d date;
begin
  select * into a from public.appointments where id = p_appointment_id;
  if a.id is null then raise exception 'Turno inexistente'; end if;
  if a.service_id is null then return; end if;
  for d in select generate_series(current_date, current_date + p_days, interval '1 day')::date loop
    return query
      select s.therapist_id, s.therapist_name, s.slot_start, s.slot_end
      from public.available_slots(d, a.service_id, null) s
      -- prioriza mismo profesional y misma franja horaria
      order by (s.therapist_id = a.therapist_id) desc,
               abs(extract(epoch from (s.slot_start::time - a.starts_at::time)))
      limit p_limit;
    exit when found;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Ficha resumen del cliente (historial agregado)
-- -----------------------------------------------------------------------------
create or replace view public.client_stats
with (security_invoker = true) as
select
  c.id as client_id,
  c.center_id,
  count(a.id) filter (where a.status = 'completed')           as attended,
  count(a.id) filter (where a.status = 'cancelled')           as cancelled,
  count(a.id) filter (where a.status = 'no_show')             as no_shows,
  count(a.id) filter (where a.status in ('pending','confirmed') and a.starts_at > now()) as upcoming,
  coalesce((select sum(p.amount) from public.payments p where p.client_id = c.id and p.status = 'paid'), 0) as total_spent,
  max(a.starts_at) filter (where a.status = 'completed')      as last_visit,
  min(a.starts_at) filter (where a.status in ('pending','confirmed') and a.starts_at > now()) as next_visit
from public.clients c
left join public.appointments a on a.client_id = c.id
where c.deleted_at is null
group by c.id;

-- Vista enriquecida para la agenda (una sola consulta para el calendario)
create or replace view public.appointments_view
with (security_invoker = true) as
select
  a.*,
  c.first_name || ' ' || c.last_name as client_name,
  coalesce(c.whatsapp, c.phone)      as client_phone,
  p.full_name                        as therapist_name,
  p.color_hex                        as therapist_color,
  coalesce(s.name, cb.name)          as service_name,
  s.color_hex                        as service_color,
  coalesce((select sum(py.amount) from public.payments py where py.appointment_id = a.id and py.status = 'paid'), 0) as paid_amount
from public.appointments a
join public.clients  c on c.id = a.client_id
join public.profiles p on p.id = a.therapist_id
left join public.services s  on s.id = a.service_id
left join public.combos   cb on cb.id = a.combo_id;

-- -----------------------------------------------------------------------------
-- Dashboard gerencial (una llamada → todos los KPIs)
-- -----------------------------------------------------------------------------
create or replace function public.dashboard_summary(p_from date default null, p_to date default null)
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  tz text := coalesce((select timezone from public.centers where id = public.current_center_id()), 'America/Argentina/Buenos_Aires');
  v_today date := (now() at time zone tz)::date;
  v_from date := coalesce(p_from, date_trunc('month', v_today)::date);
  v_to   date := coalesce(p_to, v_today);
  r_from timestamptz := (v_from::timestamp at time zone tz);
  r_to   timestamptz := ((v_to + 1)::timestamp at time zone tz);
  t_from timestamptz := (v_today::timestamp at time zone tz);
  t_to   timestamptz := ((v_today + 1)::timestamp at time zone tz);
  result jsonb;
begin
  select jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'today_appointments', (select count(*) from public.appointments
                           where starts_at >= t_from and starts_at < t_to and status <> 'cancelled'),
    'today_by_status', (select coalesce(jsonb_object_agg(status, n), '{}') from (
                          select status, count(*) n from public.appointments
                          where starts_at >= t_from and starts_at < t_to group by status) x),
    'revenue_today', (select coalesce(sum(amount), 0) from public.payments
                      where status = 'paid' and paid_at >= t_from and paid_at < t_to),
    'revenue_period', (select coalesce(sum(amount), 0) from public.payments
                       where status = 'paid' and paid_at >= r_from and paid_at < r_to),
    'revenue_by_method', (select coalesce(jsonb_object_agg(method, total), '{}') from (
                            select method, sum(amount) total from public.payments
                            where status = 'paid' and paid_at >= r_from and paid_at < r_to group by method) x),
    'revenue_by_day', (select coalesce(jsonb_agg(jsonb_build_object('date', d, 'total', total) order by d), '[]') from (
                         select (paid_at at time zone tz)::date d, sum(amount) total from public.payments
                         where status = 'paid' and paid_at >= r_from and paid_at < r_to group by 1) x),
    'new_clients', (select count(*) from public.clients
                    where deleted_at is null and created_at >= r_from and created_at < r_to),
    'active_clients', (select count(distinct client_id) from public.appointments
                       where status = 'completed' and starts_at >= now() - interval '90 days'),
    'top_services', (select coalesce(jsonb_agg(x order by x.count desc), '[]') from (
                       select s.name, count(*) as count, sum(a.final_price) as revenue
                       from public.appointments a join public.services s on s.id = a.service_id
                       where a.status = 'completed' and a.starts_at >= r_from and a.starts_at < r_to
                       group by s.name order by count(*) desc limit 5) x),
    'bottom_services', (select coalesce(jsonb_agg(x order by x.count), '[]') from (
                          select s.name, count(a.id) as count
                          from public.services s
                          left join public.appointments a on a.service_id = s.id and a.status = 'completed'
                               and a.starts_at >= r_from and a.starts_at < r_to
                          where s.is_active and s.deleted_at is null
                          group by s.name order by count(a.id) asc limit 5) x),
    'peak_hours', (select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', n) order by h), '[]') from (
                     select extract(hour from starts_at at time zone tz)::int h, count(*) n
                     from public.appointments
                     where status <> 'cancelled' and starts_at >= r_from and starts_at < r_to group by 1) x),
    'peak_weekdays', (select coalesce(jsonb_agg(jsonb_build_object('weekday', d, 'count', n) order by d), '[]') from (
                        select extract(isodow from starts_at at time zone tz)::int d, count(*) n
                        from public.appointments
                        where status <> 'cancelled' and starts_at >= r_from and starts_at < r_to group by 1) x),
    'cancellation_rate', (select round(100.0 * count(*) filter (where status = 'cancelled') / nullif(count(*), 0), 1)
                          from public.appointments where starts_at >= r_from and starts_at < r_to),
    'no_show_rate', (select round(100.0 * count(*) filter (where status = 'no_show') / nullif(count(*), 0), 1)
                     from public.appointments where starts_at >= r_from and starts_at < r_to),
    'pending_payments', (select count(*) from public.appointments_view
                         where status = 'completed' and paid_amount < final_price
                           and starts_at >= now() - interval '60 days')
  ) into result;
  return result;
end $$;

-- -----------------------------------------------------------------------------
-- Reportes (filas planas → la app exporta a PDF / Excel)
-- p_group: 'day' | 'week' | 'month' | 'year'
-- -----------------------------------------------------------------------------
create or replace function public.report_sales(p_from date, p_to date, p_group text default 'day')
returns table (period date, payments_count bigint, total numeric, cash numeric, transfer numeric, card numeric, mercado_pago numeric)
language sql stable security invoker set search_path = public as $$
  select date_trunc(p_group, paid_at at time zone 'America/Argentina/Buenos_Aires')::date as period,
         count(*),
         sum(amount),
         sum(amount) filter (where method = 'cash'),
         sum(amount) filter (where method = 'transfer'),
         sum(amount) filter (where method = 'card'),
         sum(amount) filter (where method = 'mercado_pago')
  from public.payments
  where status = 'paid'
    and paid_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
    and paid_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  group by 1 order by 1
$$;

create or replace function public.report_appointments(p_from date, p_to date, p_group text default 'day')
returns table (period date, total bigint, completed bigint, cancelled bigint, no_show bigint, rescheduled bigint, pending bigint)
language sql stable security invoker set search_path = public as $$
  select date_trunc(p_group, starts_at at time zone 'America/Argentina/Buenos_Aires')::date,
         count(*),
         count(*) filter (where status = 'completed'),
         count(*) filter (where status = 'cancelled'),
         count(*) filter (where status = 'no_show'),
         count(*) filter (where reschedule_count > 0),
         count(*) filter (where status in ('pending','confirmed'))
  from public.appointments
  where starts_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
    and starts_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  group by 1 order by 1
$$;

create or replace function public.report_services(p_from date, p_to date)
returns table (service_name text, category text, sessions bigint, revenue numeric, avg_ticket numeric)
language sql stable security invoker set search_path = public as $$
  select s.name, sc.name, count(a.id), coalesce(sum(a.final_price), 0), round(avg(a.final_price), 2)
  from public.services s
  left join public.service_categories sc on sc.id = s.category_id
  left join public.appointments a on a.service_id = s.id and a.status = 'completed'
       and a.starts_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
       and a.starts_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  where s.deleted_at is null
  group by s.name, sc.name order by 3 desc
$$;

create or replace function public.report_cancellations(p_from date, p_to date)
returns table (event_date date, event text, client_name text, service_name text, reason text, performed_by text)
language sql stable security invoker set search_path = public as $$
  select (e.created_at at time zone 'America/Argentina/Buenos_Aires')::date,
         e.event::text, av.client_name, av.service_name, e.reason, p.full_name
  from public.appointment_events e
  join public.appointments_view av on av.id = e.appointment_id
  left join public.profiles p on p.id = e.performed_by
  where e.event in ('cancelled','rescheduled','no_show')
    and e.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
    and e.created_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  order by e.created_at desc
$$;

create or replace function public.report_clients(p_from date, p_to date)
returns table (client_id uuid, client_name text, visits bigint, total_spent numeric, last_visit timestamptz, cancellations bigint)
language sql stable security invoker set search_path = public as $$
  select c.id, c.first_name || ' ' || c.last_name,
         count(a.id) filter (where a.status = 'completed'),
         coalesce((select sum(p.amount) from public.payments p where p.client_id = c.id and p.status = 'paid'
                   and p.paid_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
                   and p.paid_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')), 0),
         max(a.starts_at) filter (where a.status = 'completed'),
         count(a.id) filter (where a.status = 'cancelled')
  from public.clients c
  left join public.appointments a on a.client_id = c.id
       and a.starts_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
       and a.starts_at <  ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  where c.deleted_at is null
  group by c.id order by 4 desc
$$;

-- Administración de usuarios
create or replace function public.admin_update_user(p_user_id uuid, p_role public.user_role, p_active boolean)
returns public.profiles
language plpgsql security invoker set search_path = public as $$
declare r public.profiles;
begin
  if not public.is_admin() then raise exception 'Solo administradores'; end if;
  update public.profiles set role = p_role, is_active = p_active
  where id = p_user_id and center_id = public.current_center_id()
  returning * into r;
  return r;
end $$;

-- Registrar token FCM del dispositivo
create or replace function public.register_fcm_token(p_token text)
returns void language sql security invoker set search_path = public as $$
  update public.profiles
     set fcm_tokens = (select array_agg(distinct t) from unnest(array_append(fcm_tokens, p_token)) t)
   where id = auth.uid()
$$;

grant execute on all functions in schema public to authenticated;
revoke execute on function public.schedule_reminders(uuid) from authenticated;
grant select on public.client_stats, public.appointments_view to authenticated;
