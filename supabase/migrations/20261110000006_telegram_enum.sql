-- =============================================================================
-- Agenda Wellness · Migración 0006 · Nuevo canal Telegram
-- ALTER TYPE ... ADD VALUE va en su propia migración: el valor nuevo no puede
-- usarse dentro de la misma transacción en la que se crea.
-- =============================================================================
alter type public.notification_channel add value if not exists 'telegram';

-- Nuevos tipos de notificación interna
alter table public.internal_notifications drop constraint if exists internal_notifications_kind_check;
alter table public.internal_notifications add constraint internal_notifications_kind_check
  check (kind in ('upcoming_appointment','new_client','cancellation','pending_payment','system',
                  'client_confirmation','reschedule_request','backup'));
