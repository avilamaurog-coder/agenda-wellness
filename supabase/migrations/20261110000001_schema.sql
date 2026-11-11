-- =============================================================================
-- Agenda Wellness · Migración 0001 · Esquema base
-- PostgreSQL 15+ (Supabase)
-- =============================================================================
-- Convenciones:
--   * PK uuid (gen_random_uuid)
--   * timestamptz en UTC; la app convierte a America/Argentina/Buenos_Aires
--   * Montos en numeric(12,2) (ARS)
--   * Soft-delete con deleted_at en entidades de negocio
--   * Multi-sede preparado vía center_id (un centro por defecto)
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "btree_gist";   -- exclusión de solapamiento de turnos
create extension if not exists "pg_trgm";      -- búsqueda difusa de clientes

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------
create type public.user_role          as enum ('admin', 'receptionist', 'therapist');
create type public.appointment_status as enum ('pending', 'confirmed', 'completed', 'cancelled', 'no_show');
create type public.payment_method     as enum ('cash', 'transfer', 'card', 'mercado_pago');
create type public.payment_status     as enum ('pending', 'paid', 'refunded', 'void');
create type public.notification_channel as enum ('whatsapp', 'email', 'push');
create type public.reminder_status    as enum ('scheduled', 'sent', 'failed', 'skipped');
create type public.discount_type      as enum ('percentage', 'fixed');
create type public.appointment_event  as enum ('created', 'updated', 'rescheduled', 'cancelled', 'confirmed', 'completed', 'no_show');

-- -----------------------------------------------------------------------------
-- Centros (preparado para multi-sede / SaaS)
-- -----------------------------------------------------------------------------
create table public.centers (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  legal_name   text,
  cuit         text,
  phone        text,
  email        text,
  address      text,
  timezone     text not null default 'America/Argentina/Buenos_Aires',
  opening_time time not null default '09:00',
  closing_time time not null default '21:00',
  slot_minutes int  not null default 15 check (slot_minutes in (5, 10, 15, 30, 60)),
  logo_url     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Perfiles de usuario (1:1 con auth.users)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  center_id   uuid not null references public.centers(id),
  full_name   text not null,
  email       text not null,
  phone       text,
  role        public.user_role not null default 'receptionist',
  avatar_url  text,
  color_hex   text not null default '#7C9A92' check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  is_active   boolean not null default true,
  fcm_tokens  text[] not null default '{}',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index profiles_center_role_idx on public.profiles(center_id, role) where is_active;

-- Horario laboral por profesional (0 = domingo … 6 = sábado)
create table public.therapist_schedules (
  id           uuid primary key default gen_random_uuid(),
  therapist_id uuid not null references public.profiles(id) on delete cascade,
  weekday      smallint not null check (weekday between 0 and 6),
  start_time   time not null,
  end_time     time not null,
  check (end_time > start_time),
  unique (therapist_id, weekday, start_time)
);

-- Bloqueos de agenda (vacaciones, licencias, feriados)
create table public.schedule_blocks (
  id           uuid primary key default gen_random_uuid(),
  center_id    uuid not null references public.centers(id),
  therapist_id uuid references public.profiles(id) on delete cascade, -- null = todo el centro
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  reason       text,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  check (ends_at > starts_at)
);

-- -----------------------------------------------------------------------------
-- Clientes
-- -----------------------------------------------------------------------------
create table public.clients (
  id                uuid primary key default gen_random_uuid(),
  center_id         uuid not null references public.centers(id),
  first_name        text not null,
  last_name         text not null,
  dni               text,
  phone             text,
  whatsapp          text,
  email             text,
  birth_date        date,
  address           text,
  observations      text,
  allergies         text,
  contraindications text,
  internal_notes    text,
  accepts_reminders boolean not null default true,
  preferred_channel public.notification_channel not null default 'whatsapp',
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  search_vector     tsvector generated always as (
    to_tsvector('simple',
      coalesce(first_name,'') || ' ' || coalesce(last_name,'') || ' ' ||
      coalesce(dni,'') || ' ' || coalesce(phone,'') || ' ' || coalesce(email,''))
  ) stored,
  constraint clients_email_chk check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
create unique index clients_center_dni_uk on public.clients(center_id, dni) where dni is not null and deleted_at is null;
create index clients_search_idx on public.clients using gin(search_vector);
create index clients_name_trgm_idx on public.clients using gin((first_name || ' ' || last_name) gin_trgm_ops);
create index clients_birth_md_idx on public.clients ((extract(month from birth_date)), (extract(day from birth_date)));

-- -----------------------------------------------------------------------------
-- Catálogo de servicios
-- -----------------------------------------------------------------------------
create table public.service_categories (
  id         uuid primary key default gen_random_uuid(),
  center_id  uuid not null references public.centers(id),
  name       text not null,
  icon       text,
  sort_order int not null default 0,
  unique (center_id, name)
);

create table public.services (
  id               uuid primary key default gen_random_uuid(),
  center_id        uuid not null references public.centers(id),
  category_id      uuid references public.service_categories(id) on delete set null,
  name             text not null,
  description      text,
  duration_minutes int not null check (duration_minutes between 5 and 480),
  buffer_minutes   int not null default 0 check (buffer_minutes between 0 and 120),
  price            numeric(12,2) not null check (price >= 0),
  promo_price      numeric(12,2) check (promo_price is null or promo_price >= 0),
  promo_valid_until date,
  image_url        text,
  color_hex        text check (color_hex is null or color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  constraint services_promo_lt_price check (promo_price is null or promo_price < price),
  unique (center_id, name)
);
create index services_center_active_idx on public.services(center_id) where is_active and deleted_at is null;

-- Profesionales habilitados por servicio (N:M)
create table public.service_therapists (
  service_id   uuid not null references public.services(id) on delete cascade,
  therapist_id uuid not null references public.profiles(id) on delete cascade,
  primary key (service_id, therapist_id)
);

-- Historial de precios (se completa por trigger)
create table public.service_price_history (
  id              uuid primary key default gen_random_uuid(),
  service_id      uuid not null references public.services(id) on delete cascade,
  old_price       numeric(12,2),
  new_price       numeric(12,2) not null,
  old_promo_price numeric(12,2),
  new_promo_price numeric(12,2),
  changed_by      uuid references public.profiles(id),
  changed_at      timestamptz not null default now()
);
create index service_price_history_service_idx on public.service_price_history(service_id, changed_at desc);

-- Combos
create table public.combos (
  id          uuid primary key default gen_random_uuid(),
  center_id   uuid not null references public.centers(id),
  name        text not null,
  description text,
  price       numeric(12,2) not null check (price >= 0),
  image_url   text,
  is_active   boolean not null default true,
  valid_from  date,
  valid_until date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (center_id, name)
);

create table public.combo_items (
  combo_id   uuid not null references public.combos(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete restrict,
  sort_order int not null default 0,
  primary key (combo_id, service_id)
);

-- Promociones / descuentos
create table public.promotions (
  id             uuid primary key default gen_random_uuid(),
  center_id      uuid not null references public.centers(id),
  name           text not null,
  code           text,
  discount_type  public.discount_type not null,
  discount_value numeric(12,2) not null check (discount_value > 0),
  service_id     uuid references public.services(id) on delete cascade, -- null = aplica a todo
  starts_on      date not null,
  ends_on        date not null,
  max_uses       int,
  uses_count     int not null default 0,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  check (ends_on >= starts_on),
  check (discount_type <> 'percentage' or discount_value <= 100)
);
create unique index promotions_code_uk on public.promotions(center_id, upper(code)) where code is not null;

-- -----------------------------------------------------------------------------
-- Turnos
-- -----------------------------------------------------------------------------
create table public.appointments (
  id                   uuid primary key default gen_random_uuid(),
  center_id            uuid not null references public.centers(id),
  client_id            uuid not null references public.clients(id),
  therapist_id         uuid not null references public.profiles(id),
  service_id           uuid references public.services(id),
  combo_id             uuid references public.combos(id),
  starts_at            timestamptz not null,
  ends_at              timestamptz not null,
  status               public.appointment_status not null default 'pending',
  price                numeric(12,2) not null default 0 check (price >= 0),
  discount_amount      numeric(12,2) not null default 0 check (discount_amount >= 0),
  final_price          numeric(12,2) generated always as (greatest(price - discount_amount, 0)) stored,
  promotion_id         uuid references public.promotions(id),
  notes                text,
  cancellation_reason  text,
  cancelled_at         timestamptz,
  cancelled_by         uuid references public.profiles(id),
  rescheduled_from_id  uuid references public.appointments(id),
  reschedule_count     int not null default 0,
  confirmed_at         timestamptz,
  completed_at         timestamptz,
  created_by           uuid references public.profiles(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (ends_at > starts_at),
  check (service_id is not null or combo_id is not null),
  -- Un profesional no puede tener dos turnos activos superpuestos
  constraint appointments_no_overlap exclude using gist (
    therapist_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('pending', 'confirmed'))
);
create index appointments_center_range_idx on public.appointments(center_id, starts_at);
create index appointments_therapist_range_idx on public.appointments(therapist_id, starts_at);
create index appointments_client_idx on public.appointments(client_id, starts_at desc);
create index appointments_status_idx on public.appointments(center_id, status, starts_at);

-- Bitácora de eventos del turno (cancelaciones, reprogramaciones, auditoría)
create table public.appointment_events (
  id             uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  event          public.appointment_event not null,
  old_starts_at  timestamptz,
  new_starts_at  timestamptz,
  old_status     public.appointment_status,
  new_status     public.appointment_status,
  reason         text,
  performed_by   uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index appointment_events_appt_idx on public.appointment_events(appointment_id, created_at);
create index appointment_events_event_idx on public.appointment_events(event, created_at);

-- -----------------------------------------------------------------------------
-- Pagos
-- -----------------------------------------------------------------------------
create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  center_id       uuid not null references public.centers(id),
  appointment_id  uuid references public.appointments(id) on delete set null,
  client_id       uuid not null references public.clients(id),
  amount          numeric(12,2) not null check (amount > 0),
  method          public.payment_method not null,
  status          public.payment_status not null default 'paid',
  reference       text,         -- nro. de operación / transferencia / MP payment_id
  notes           text,
  paid_at         timestamptz not null default now(),
  registered_by   uuid references public.profiles(id),
  created_at      timestamptz not null default now()
);
create index payments_center_paid_idx on public.payments(center_id, paid_at) where status = 'paid';
create index payments_client_idx on public.payments(client_id, paid_at desc);
create index payments_appointment_idx on public.payments(appointment_id);

-- -----------------------------------------------------------------------------
-- Historia clínica / fichas
-- -----------------------------------------------------------------------------
create table public.clinical_records (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.clients(id) on delete cascade,
  appointment_id  uuid references public.appointments(id) on delete set null,
  therapist_id    uuid references public.profiles(id),
  record_date     date not null default current_date,
  evaluation      text,
  observations    text,
  treatment_goals text,
  evolution       text,
  pain_scale      smallint check (pain_scale between 0 and 10),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index clinical_records_client_idx on public.clinical_records(client_id, record_date desc);

create table public.clinical_photos (
  id           uuid primary key default gen_random_uuid(),
  record_id    uuid not null references public.clinical_records(id) on delete cascade,
  storage_path text not null,   -- bucket privado "clinical-photos"
  caption      text,
  taken_at     timestamptz not null default now(),
  uploaded_by  uuid references public.profiles(id)
);

-- -----------------------------------------------------------------------------
-- Recordatorios y notificaciones
-- -----------------------------------------------------------------------------
create table public.message_templates (
  id         uuid primary key default gen_random_uuid(),
  center_id  uuid not null references public.centers(id),
  channel    public.notification_channel not null,
  hours_before int not null check (hours_before in (2, 24, 48)),
  subject    text,
  body       text not null,  -- variables: {{nombre}}, {{servicio}}, {{fecha}}, {{hora}}, {{profesional}}, {{centro}}
  is_active  boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (center_id, channel, hours_before)
);

create table public.appointment_reminders (
  id             uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  channel        public.notification_channel not null,
  hours_before   int not null,
  scheduled_for  timestamptz not null,
  status         public.reminder_status not null default 'scheduled',
  attempts       int not null default 0,
  sent_at        timestamptz,
  provider_id    text,
  error          text,
  unique (appointment_id, channel, hours_before)
);
create index appointment_reminders_due_idx on public.appointment_reminders(scheduled_for) where status = 'scheduled';

-- Notificaciones internas (campana de la app)
create table public.internal_notifications (
  id          uuid primary key default gen_random_uuid(),
  center_id   uuid not null references public.centers(id),
  user_id     uuid references public.profiles(id) on delete cascade, -- null = todo el staff
  kind        text not null check (kind in ('upcoming_appointment','new_client','cancellation','pending_payment','system')),
  title       text not null,
  body        text,
  payload     jsonb not null default '{}',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index internal_notifications_user_idx on public.internal_notifications(center_id, user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Auditoría genérica
-- -----------------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  table_name  text not null,
  record_id   uuid,
  action      text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  user_id     uuid,
  created_at  timestamptz not null default now()
);
create index audit_log_table_record_idx on public.audit_log(table_name, record_id);
