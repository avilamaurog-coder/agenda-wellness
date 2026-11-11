-- =============================================================================
-- Agenda Wellness · Migración 0008 · Backup diario a la nube
-- 03:00 hora Argentina = 06:00 UTC. Usa los mismos secretos de Vault que los recordatorios.
-- =============================================================================
select cron.schedule(
  'daily-cloud-backup',
  '0 6 * * *',
  $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/backup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body    := '{"trigger":"scheduled"}'::jsonb,
    timeout_milliseconds := 300000
  );
  $$
);
