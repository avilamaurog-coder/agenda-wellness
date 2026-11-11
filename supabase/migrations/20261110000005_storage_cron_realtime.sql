-- =============================================================================
-- Agenda Wellness · Migración 0005 · Storage, Realtime y tareas programadas
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Buckets
--   service-images  : público (catálogo)
--   avatars         : público
--   clinical-photos : PRIVADO · ruta  {center_id}/{client_id}/{uuid}.jpg
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('service-images',  'service-images',  true,  5242880,  array['image/jpeg','image/png','image/webp']),
  ('avatars',         'avatars',         true,  2097152,  array['image/jpeg','image/png','image/webp']),
  ('clinical-photos', 'clinical-photos', false, 10485760, array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

create policy "service images read"  on storage.objects for select using (bucket_id = 'service-images');
create policy "service images write" on storage.objects for all to authenticated
  using (bucket_id = 'service-images' and public.is_admin())
  with check (bucket_id = 'service-images' and public.is_admin());

create policy "avatars read"  on storage.objects for select using (bucket_id = 'avatars');
create policy "avatars write own" on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "clinical photos read" on storage.objects for select to authenticated
  using (
    bucket_id = 'clinical-photos'
    and (storage.foldername(name))[1] = public.current_center_id()::text
    and (public.is_admin() or public.therapist_has_client(((storage.foldername(name))[2])::uuid))
  );
create policy "clinical photos write" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'clinical-photos'
    and (storage.foldername(name))[1] = public.current_center_id()::text
    and (public.is_admin() or public.therapist_has_client(((storage.foldername(name))[2])::uuid))
  );
create policy "clinical photos delete" on storage.objects for delete to authenticated
  using (bucket_id = 'clinical-photos' and public.is_admin());

-- -----------------------------------------------------------------------------
-- Realtime: la agenda y la campana se actualizan en vivo
-- -----------------------------------------------------------------------------
alter publication supabase_realtime add table public.appointments;
alter publication supabase_realtime add table public.internal_notifications;

-- -----------------------------------------------------------------------------
-- pg_cron + pg_net: despachador de recordatorios cada 5 minutos
-- Requiere guardar en Vault:
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<CRON_SECRET>',              'cron_secret');
-- -----------------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'dispatch-reminders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);

-- Alerta interna "turno próximo" 30 min antes (al profesional)
create or replace function public.notify_upcoming_appointments()
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.internal_notifications(center_id, user_id, kind, title, body, payload)
  select a.center_id, a.therapist_id, 'upcoming_appointment', 'Turno en 30 minutos',
         av.client_name || ' · ' || av.service_name,
         jsonb_build_object('appointment_id', a.id)
  from public.appointments a
  join public.appointments_view av on av.id = a.id
  where a.status in ('pending','confirmed')
    and a.starts_at between now() + interval '25 minutes' and now() + interval '30 minutes'
    and not exists (select 1 from public.internal_notifications n
                    where n.kind = 'upcoming_appointment' and n.payload->>'appointment_id' = a.id::text);
end $$;

select cron.schedule('notify-upcoming', '*/5 * * * *', $$ select public.notify_upcoming_appointments(); $$);

-- Marca automáticamente "ausente" los turnos confirmados/pendientes no cerrados 3 h después
select cron.schedule('auto-no-show', '0 * * * *', $$
  update public.appointments set status = 'no_show'
  where status in ('pending','confirmed') and ends_at < now() - interval '3 hours';
$$);
