-- Tarjetas de regalo: plantilla por producto y registro de cada tarjeta emitida.
-- Aditiva e idempotente (ya aplicada en el proyecto de Supabase como agenda_tarjetas_regalo).
alter table public.products add column if not exists is_gift_card boolean not null default false;
alter table public.products add column if not exists gift_template_url text;

create or replace function public.gift_card_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select 'GC-' || upper(substr(md5(gen_random_uuid()::text), 1, 8));
$$;

create table if not exists public.gift_cards (
  id              uuid primary key default gen_random_uuid(),
  center_id       uuid not null default public.current_center_id() references public.centers(id) on delete cascade,
  product_id      uuid references public.products(id) on delete set null,
  code            text not null default public.gift_card_code(),
  recipient_name  text not null check (length(trim(recipient_name)) > 0),
  amount          numeric not null check (amount >= 0),
  valid_from      date not null,
  valid_until     date not null,
  status          text not null default 'activa' check (status in ('activa', 'canjeada', 'vencida', 'anulada')),
  redeemed_at     timestamptz,
  created_by      uuid references auth.users(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  constraint gift_cards_fechas_ok check (valid_until >= valid_from),
  constraint gift_cards_codigo_unico unique (center_id, code)
);

create index if not exists gift_cards_center_created_idx on public.gift_cards (center_id, created_at desc);

alter table public.gift_cards enable row level security;

drop policy if exists gift_cards_equipo on public.gift_cards;
create policy gift_cards_equipo on public.gift_cards
  for all to authenticated
  using (center_id = public.current_center_id())
  with check (center_id = public.current_center_id());
