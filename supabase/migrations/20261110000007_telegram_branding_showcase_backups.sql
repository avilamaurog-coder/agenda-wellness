-- =============================================================================
-- Agenda Wellness · Migración 0007
--   1. Telegram: vinculación de clientes, recordatorios y confirmación
--   2. Marca del centro: logo, contactos y catálogo público
--   3. Vitrina: productos y publicaciones promocionales
--   4. Backups automáticos a Google Drive / OneDrive
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Centro: marca, contacto y configuración de Telegram
-- -----------------------------------------------------------------------------
alter table public.centers
  add column if not exists description             text,
  add column if not exists whatsapp_contact        text,
  add column if not exists instagram               text,
  add column if not exists website                 text,
  add column if not exists public_catalog_enabled  boolean not null default true,
  add column if not exists telegram_bot_username   text,   -- sin @, ej. AgendaWellnessBot
  add column if not exists telegram_admin_chat_id  text,   -- chat que recibe avisos de confirmaciones/cancelaciones
  add column if not exists telegram_channel_id     text,   -- canal para publicar promociones (@micanal o -100…)
  add column if not exists backup_enabled          boolean not null default true;

-- -----------------------------------------------------------------------------
-- 2. Clientes: vinculación con Telegram
-- -----------------------------------------------------------------------------
alter table public.clients
  add column if not exists telegram_chat_id    text,
  add column if not exists telegram_username   text,
  add column if not exists telegram_linked_at  timestamptz,
  add column if not exists telegram_link_code  text not null default replace(gen_random_uuid()::text, '-', '');

create unique index if not exists clients_telegram_code_uk on public.clients(telegram_link_code);
create index if not exists clients_telegram_chat_idx on public.clients(telegram_chat_id) where telegram_chat_id is not null;

-- Plantillas Telegram para centros existentes (en instalaciones nuevas las crea el seed)
insert into public.message_templates (center_id, channel, hours_before, subject, body)
select c.id, 'telegram', h.hours, null, h.body
from public.centers c
cross join (values
  (48, '🌿 Hola {{nombre}}! Te recordamos tu turno de {{servicio}} el {{fecha}} a las {{hora}} hs con {{profesional}}. ¿Nos confirmás tu asistencia?'),
  (24, 'Hola {{nombre}}, mañana {{fecha}} a las {{hora}} hs te esperamos para tu {{servicio}}.'),
  (2,  '¡Hola {{nombre}}! Te esperamos hoy a las {{hora}} hs en {{centro}} 💆')
) as h(hours, body)
on conflict (center_id, channel, hours_before) do nothing;

-- schedule_reminders: incluye Telegram cuando el cliente está vinculado
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
          (t.channel = 'telegram' and c.telegram_chat_id is not null) or
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
revoke execute on function public.schedule_reminders(uuid) from authenticated;

-- Al vincular Telegram, reprogramar recordatorios de los turnos futuros del cliente
create or replace function public.tg_client_telegram_linked()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.telegram_chat_id is distinct from old.telegram_chat_id then
    for r in select id from public.appointments
             where client_id = new.id and status in ('pending','confirmed') and starts_at > now()
    loop
      perform public.schedule_reminders(r.id);
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists client_telegram_linked on public.clients;
create trigger client_telegram_linked after update of telegram_chat_id on public.clients
  for each row execute function public.tg_client_telegram_linked();

-- Nuevo código de vinculación (por si el enlace se compartió por error)
create or replace function public.regenerate_telegram_code(p_client_id uuid)
returns text language sql security invoker set search_path = public as $$
  update public.clients set telegram_link_code = replace(gen_random_uuid()::text, '-', '')
  where id = p_client_id
  returning telegram_link_code
$$;

-- Desvincular Telegram de un cliente
create or replace function public.unlink_telegram(p_client_id uuid)
returns void language sql security invoker set search_path = public as $$
  update public.clients
     set telegram_chat_id = null, telegram_username = null, telegram_linked_at = null,
         telegram_link_code = replace(gen_random_uuid()::text, '-', '')
   where id = p_client_id
$$;

-- -----------------------------------------------------------------------------
-- 3. Vitrina: productos y publicaciones
-- -----------------------------------------------------------------------------
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  center_id    uuid not null references public.centers(id),
  name         text not null,
  description  text,
  category     text,
  brand        text,
  price        numeric(12,2) not null check (price >= 0),
  promo_price  numeric(12,2) check (promo_price is null or promo_price >= 0),
  stock        int check (stock is null or stock >= 0),  -- null = no controla stock
  image_url    text,
  is_active    boolean not null default true,
  is_featured  boolean not null default false,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint products_promo_lt_price check (promo_price is null or promo_price < price),
  unique (center_id, name)
);
create index if not exists products_center_active_idx on public.products(center_id, sort_order) where is_active;

create table if not exists public.promo_posts (
  id                     uuid primary key default gen_random_uuid(),
  center_id              uuid not null references public.centers(id),
  title                  text not null,
  body                   text,
  image_url              text,
  service_id             uuid references public.services(id) on delete set null,
  combo_id               uuid references public.combos(id) on delete set null,
  product_id             uuid references public.products(id) on delete set null,
  cta_label              text not null default 'Reservar por WhatsApp',
  starts_on              date not null default current_date,
  ends_on                date,
  is_active              boolean not null default true,
  is_featured            boolean not null default false,
  sort_order             int not null default 0,
  published_telegram_at  timestamptz,
  created_by             uuid references public.profiles(id),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);
create index if not exists promo_posts_center_idx on public.promo_posts(center_id, starts_on desc);

do $$
declare t text;
begin
  foreach t in array array['products','promo_posts'] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function public.tg_set_updated_at()', t);
    execute format('drop trigger if exists default_center on public.%I', t);
    execute format('create trigger default_center before insert on public.%I
                    for each row execute function public.tg_default_center()', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

create policy products_select on public.products for select to authenticated
  using (center_id = public.current_center_id());
create policy products_write on public.products for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

create policy promo_posts_select on public.promo_posts for select to authenticated
  using (center_id = public.current_center_id());
create policy promo_posts_write on public.promo_posts for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

-- -----------------------------------------------------------------------------
-- 4. Backups
-- -----------------------------------------------------------------------------
create table if not exists public.backups (
  id           uuid primary key default gen_random_uuid(),
  center_id    uuid references public.centers(id),
  provider     text not null check (provider in ('google_drive','onedrive')),
  trigger      text not null default 'scheduled' check (trigger in ('scheduled','manual')),
  status       text not null default 'running' check (status in ('running','success','failed')),
  file_name    text,
  remote_id    text,
  size_bytes   bigint,
  row_counts   jsonb,
  encrypted    boolean not null default false,
  error        text,
  requested_by uuid references public.profiles(id),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index if not exists backups_started_idx on public.backups(started_at desc);
alter table public.backups enable row level security;
alter table public.backups force row level security;
create policy backups_select on public.backups for select to authenticated using (public.is_admin());

-- Secretos de integraciones que rotan (refresh token de OneDrive). Esquema no expuesto por la API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.integration_secrets (
  name       text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

create or replace function public.get_integration_secret(p_name text)
returns text language sql security definer set search_path = private, public as $$
  select value from private.integration_secrets where name = p_name
$$;
create or replace function public.set_integration_secret(p_name text, p_value text)
returns void language sql security definer set search_path = private, public as $$
  insert into private.integration_secrets(name, value) values (p_name, p_value)
  on conflict (name) do update set value = excluded.value, updated_at = now()
$$;
revoke execute on function public.get_integration_secret(text) from public, anon, authenticated;
revoke execute on function public.set_integration_secret(text, text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.get_integration_secret(text) to service_role;
    grant execute on function public.set_integration_secret(text, text) to service_role;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Storage: logo y vitrina (públicos, escritura solo admin)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('branding', 'branding', true, 2097152, array['image/jpeg','image/png','image/webp','image/svg+xml']),
  ('showcase', 'showcase', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "branding read"  on storage.objects for select using (bucket_id = 'branding');
create policy "branding write" on storage.objects for all to authenticated
  using (bucket_id = 'branding' and public.is_admin()
         and (storage.foldername(name))[1] = public.current_center_id()::text)
  with check (bucket_id = 'branding' and public.is_admin()
              and (storage.foldername(name))[1] = public.current_center_id()::text);

create policy "showcase read"  on storage.objects for select using (bucket_id = 'showcase');
create policy "showcase write" on storage.objects for all to authenticated
  using (bucket_id = 'showcase' and public.is_admin()
         and (storage.foldername(name))[1] = public.current_center_id()::text)
  with check (bucket_id = 'showcase' and public.is_admin()
              and (storage.foldername(name))[1] = public.current_center_id()::text);

-- -----------------------------------------------------------------------------
-- 6. RPC públicas (rol anon): marca y catálogo. Solo datos de difusión.
-- -----------------------------------------------------------------------------
create or replace function public.public_branding(p_center_id uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'logo_url', c.logo_url, 'description', c.description,
    'whatsapp', c.whatsapp_contact, 'instagram', c.instagram, 'address', c.address,
    'phone', c.phone, 'website', c.website, 'telegram_bot', c.telegram_bot_username,
    'opening_time', c.opening_time, 'closing_time', c.closing_time
  )
  from public.centers c
  where (p_center_id is null or c.id = p_center_id)
  order by c.created_at
  limit 1
$$;

create or replace function public.public_catalog(p_center_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_center uuid;
  v_enabled boolean;
begin
  select id, public_catalog_enabled into v_center, v_enabled
  from public.centers where (p_center_id is null or id = p_center_id)
  order by created_at limit 1;

  if v_center is null or not v_enabled then
    return jsonb_build_object('enabled', false);
  end if;

  return jsonb_build_object(
    'enabled', true,
    'center', public.public_branding(v_center),
    'posts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'title', p.title, 'body', p.body, 'image_url', p.image_url,
        'cta_label', p.cta_label, 'ends_on', p.ends_on, 'is_featured', p.is_featured,
        'service', s.name, 'product', pr.name, 'combo', cb.name
      ) order by p.is_featured desc, p.sort_order, p.starts_on desc)
      from public.promo_posts p
      left join public.services s on s.id = p.service_id
      left join public.products pr on pr.id = p.product_id
      left join public.combos cb on cb.id = p.combo_id
      where p.center_id = v_center and p.is_active
        and p.starts_on <= current_date and (p.ends_on is null or p.ends_on >= current_date)
    ), '[]'),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'description', s.description, 'category', sc.name,
        'duration_minutes', s.duration_minutes, 'price', s.price,
        'promo_price', case when s.promo_price is not null
                             and (s.promo_valid_until is null or s.promo_valid_until >= current_date)
                            then s.promo_price end,
        'image_url', s.image_url, 'color_hex', s.color_hex
      ) order by sc.sort_order nulls last, s.name)
      from public.services s left join public.service_categories sc on sc.id = s.category_id
      where s.center_id = v_center and s.is_active and s.deleted_at is null
    ), '[]'),
    'combos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cb.id, 'name', cb.name, 'description', cb.description, 'price', cb.price, 'image_url', cb.image_url,
        'services', (select jsonb_agg(s.name order by ci.sort_order)
                     from public.combo_items ci join public.services s on s.id = ci.service_id
                     where ci.combo_id = cb.id)
      ) order by cb.name)
      from public.combos cb
      where cb.center_id = v_center and cb.is_active
        and (cb.valid_until is null or cb.valid_until >= current_date)
    ), '[]'),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'description', p.description, 'category', p.category,
        'brand', p.brand, 'price', p.price, 'promo_price', p.promo_price, 'image_url', p.image_url,
        'in_stock', p.stock is null or p.stock > 0, 'is_featured', p.is_featured
      ) order by p.is_featured desc, p.sort_order, p.name)
      from public.products p where p.center_id = v_center and p.is_active
    ), '[]')
  );
end $$;

grant execute on function public.public_branding(uuid) to anon, authenticated;
grant execute on function public.public_catalog(uuid) to anon, authenticated;
grant select, insert, update, delete on public.products, public.promo_posts, public.backups to authenticated;
grant execute on function public.regenerate_telegram_code(uuid), public.unlink_telegram(uuid) to authenticated;
