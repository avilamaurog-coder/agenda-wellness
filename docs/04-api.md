# 4. APIs REST

Agenda Wellness usa la API REST que Supabase genera sobre PostgreSQL (PostgREST), más funciones RPC y dos Edge Functions. Toda la autorización la resuelve RLS según el JWT del usuario.

**Base URL:** `https://<project-ref>.supabase.co`

**Headers comunes**

```http
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <access_token del usuario>
Content-Type: application/json
Prefer: return=representation      # para recibir la fila creada/actualizada
```

## 4.1 Autenticación — `/auth/v1`

| Método | Endpoint | Descripción |
|---|---|---|
| POST | `/auth/v1/signup` | Registro `{ email, password, data: { full_name, phone } }` |
| POST | `/auth/v1/token?grant_type=password` | Login `{ email, password }` → `access_token`, `refresh_token` |
| POST | `/auth/v1/token?grant_type=refresh_token` | Renovar sesión |
| POST | `/auth/v1/recover` | Enviar email de recuperación `{ email }` |
| PUT | `/auth/v1/user` | Cambiar contraseña `{ password }` |
| POST | `/auth/v1/logout` | Cerrar sesión |

## 4.2 Clientes — `/rest/v1/clients`

| Método | Endpoint | Descripción |
|---|---|---|
| GET | `/rest/v1/clients?deleted_at=is.null&order=last_name&limit=30&offset=0` | Listado paginado |
| GET | `/rest/v1/clients?or=(first_name.ilike.*ana*,dni.ilike.*301*)` | Búsqueda |
| GET | `/rest/v1/clients?id=eq.{id}` | Detalle |
| GET | `/rest/v1/client_stats?client_id=eq.{id}` | Historial agregado |
| POST | `/rest/v1/clients` | Alta |
| PATCH | `/rest/v1/clients?id=eq.{id}` | Edición |
| PATCH | `/rest/v1/clients?id=eq.{id}` `{ "deleted_at": "now" }` | Baja lógica (admin) |

```json
POST /rest/v1/clients
{
  "first_name": "Ana", "last_name": "Pérez", "dni": "30123456",
  "phone": "3764123456", "whatsapp": "3764123456", "email": "ana@mail.com",
  "birth_date": "1990-05-03", "allergies": "Aceite de almendras",
  "accepts_reminders": true, "preferred_channel": "whatsapp"
}
```

## 4.3 Servicios, combos y precios

| Método | Endpoint | Descripción |
|---|---|---|
| GET | `/rest/v1/services?select=*,category:service_categories(name),service_therapists(therapist_id)&deleted_at=is.null` | Catálogo |
| POST | `/rest/v1/services` | Alta (admin) |
| PATCH | `/rest/v1/services?id=eq.{id}` | Edición / activar-desactivar (admin) |
| GET | `/rest/v1/service_price_history?service_id=eq.{id}&order=changed_at.desc` | Historial de precios |
| POST / DELETE | `/rest/v1/service_therapists` | Profesionales habilitados |
| GET | `/rest/v1/combos?select=*,combo_items(sort_order,service:services(*))` | Combos con servicios |
| GET | `/rest/v1/service_categories?order=sort_order` | Categorías |

## 4.4 Turnos

| Método | Endpoint | Descripción |
|---|---|---|
| GET | `/rest/v1/appointments_view?starts_at=gte.{iso}&starts_at=lt.{iso}&order=starts_at` | Agenda de un rango |
| GET | `/rest/v1/appointments_view?therapist_id=eq.{id}&…` | Agenda de un profesional |
| GET | `/rest/v1/appointments_view?client_id=eq.{id}&order=starts_at.desc` | Turnos de un cliente |
| POST | `/rest/v1/appointments` | Crear turno |
| PATCH | `/rest/v1/appointments?id=eq.{id}` `{ "notes": "…" }` | Editar notas |
| POST | `/rest/v1/rpc/reschedule_appointment` | Reprogramar |
| POST | `/rest/v1/rpc/cancel_appointment` | Cancelar |
| POST | `/rest/v1/rpc/set_appointment_status` | Confirmar / completar / ausente |
| POST | `/rest/v1/rpc/available_slots` | Horarios libres |
| POST | `/rest/v1/rpc/suggest_reschedule` | Sugerencias tras cancelación |
| GET | `/rest/v1/appointment_events?appointment_id=eq.{id}&order=created_at` | Bitácora |

```json
POST /rest/v1/appointments
{
  "client_id": "…", "therapist_id": "…",
  "service_id": "20000000-0000-0000-0000-000000000002",
  "starts_at": "2026-11-15T21:00:00Z",
  "price": 0, "discount_amount": 0, "notes": "Primera vez"
}
// price 0 → se aplica el precio vigente del catálogo; ends_at se calcula solo.

POST /rest/v1/rpc/reschedule_appointment
{ "p_id": "…", "p_new_start": "2026-11-16T19:30:00Z", "p_new_therapist": null, "p_reason": "Pidió cambio" }

POST /rest/v1/rpc/cancel_appointment
{ "p_id": "…", "p_reason": "Enfermedad" }

POST /rest/v1/rpc/set_appointment_status
{ "p_id": "…", "p_status": "confirmed" }

POST /rest/v1/rpc/available_slots
{ "p_date": "2026-11-15", "p_service_id": "…", "p_therapist_id": null }
→ [{ "therapist_id": "…", "therapist_name": "Laura", "slot_start": "…", "slot_end": "…" }]
```

## 4.5 Pagos

| Método | Endpoint | Descripción |
|---|---|---|
| POST | `/rest/v1/payments` | Registrar cobro |
| GET | `/rest/v1/payments?client_id=eq.{id}&order=paid_at.desc` | Historial del cliente |
| GET | `/rest/v1/payments?appointment_id=eq.{id}` | Pagos de un turno |
| PATCH | `/rest/v1/payments?id=eq.{id}` `{ "status": "void" }` | Anular (admin) |

```json
POST /rest/v1/payments
{ "appointment_id": "…", "client_id": "…", "amount": 25000, "method": "mercado_pago", "reference": "MP-123456789" }
```

## 4.6 Historia clínica

| Método | Endpoint | Descripción |
|---|---|---|
| GET | `/rest/v1/clinical_records?client_id=eq.{id}&select=*,therapist:profiles(full_name),clinical_photos(storage_path)` | Fichas |
| POST | `/rest/v1/clinical_records` | Nueva evaluación |
| POST | `/storage/v1/object/clinical-photos/{center}/{client}/{uuid}.jpg` | Subir foto |
| POST | `/storage/v1/object/sign/clinical-photos/{path}` `{ "expiresIn": 600 }` | URL firmada |

## 4.7 Dashboard y reportes

| Método | Endpoint | Body |
|---|---|---|
| POST | `/rest/v1/rpc/dashboard_summary` | `{ "p_from": "2026-11-01", "p_to": "2026-11-10" }` |
| POST | `/rest/v1/rpc/report_sales` | `{ "p_from", "p_to", "p_group": "day\|week\|month\|year" }` |
| POST | `/rest/v1/rpc/report_appointments` | ídem |
| POST | `/rest/v1/rpc/report_services` | `{ "p_from", "p_to" }` |
| POST | `/rest/v1/rpc/report_clients` | `{ "p_from", "p_to" }` |
| POST | `/rest/v1/rpc/report_cancellations` | `{ "p_from", "p_to" }` |

Ejemplo de respuesta de `dashboard_summary`:

```json
{
  "period": { "from": "2026-11-01", "to": "2026-11-10" },
  "today_appointments": 14,
  "today_by_status": { "pending": 5, "confirmed": 7, "completed": 2 },
  "revenue_today": 187000,
  "revenue_period": 1840000,
  "revenue_by_method": { "cash": 420000, "transfer": 760000, "mercado_pago": 660000 },
  "revenue_by_day": [{ "date": "2026-11-01", "total": 210000 }],
  "new_clients": 9,
  "active_clients": 112,
  "top_services": [{ "name": "Masaje Descontracturante", "count": 38, "revenue": 1064000 }],
  "bottom_services": [{ "name": "Electrodos", "count": 2 }],
  "peak_hours": [{ "hour": 18, "count": 24 }],
  "cancellation_rate": 7.4,
  "no_show_rate": 2.1,
  "pending_payments": 3
}
```

## 4.8 Equipo, plantillas y notificaciones

| Método | Endpoint | Descripción |
|---|---|---|
| GET | `/rest/v1/profiles?order=full_name` | Staff |
| POST | `/rest/v1/rpc/admin_update_user` | `{ p_user_id, p_role, p_active }` (admin) |
| POST | `/functions/v1/invite-user` | `{ email, full_name, role }` (admin) |
| GET / PATCH | `/rest/v1/message_templates` | Plantillas de recordatorio |
| GET | `/rest/v1/internal_notifications?order=created_at.desc` | Campana |
| PATCH | `/rest/v1/internal_notifications?read_at=is.null` `{ "read_at": "now" }` | Marcar leídas |
| POST | `/rest/v1/rpc/register_fcm_token` | `{ p_token }` |

## 4.9 Edge Functions

| Función | Auth | Descripción |
|---|---|---|
| `POST /functions/v1/send-reminders` | Header `x-cron-secret` | Despacha recordatorios vencidos (la invoca pg_cron) |
| `POST /functions/v1/invite-user` | JWT de admin | Invita un miembro del staff con rol |

## 4.10 Vitrina, marca, Telegram y backups (v1.1)

| Método | Endpoint | Descripción |
|---|---|---|
| POST | `/rest/v1/rpc/public_catalog` | **Sin login** (anon). Centro, promociones vigentes, servicios, combos y productos activos |
| POST | `/rest/v1/rpc/public_branding` | **Sin login**. Nombre, logo y contacto del centro |
| GET / POST / PATCH / DELETE | `/rest/v1/products` | Productos (escritura solo admin) |
| GET / POST / PATCH / DELETE | `/rest/v1/promo_posts?select=*,service:services(name),combo:combos(name),product:products(name)` | Promociones |
| PATCH | `/rest/v1/centers?id=eq.{id}` | Datos del centro, logo, Telegram (admin) |
| POST | `/storage/v1/object/branding/{center}/logo-{uuid}.png` | Subir logo (admin) |
| POST | `/storage/v1/object/showcase/{center}/products/{uuid}.jpg` | Imágenes de vitrina (admin) |
| POST | `/rest/v1/rpc/regenerate_telegram_code` | `{ p_client_id }` → nuevo enlace de vinculación |
| POST | `/rest/v1/rpc/unlink_telegram` | `{ p_client_id }` |
| POST | `/functions/v1/telegram-webhook` | Webhook del bot (header `X-Telegram-Bot-Api-Secret-Token`) |
| POST | `/functions/v1/telegram-broadcast` | `{ post_id }` (admin): publica la promoción en el canal |
| POST | `/functions/v1/backup` | Backup manual (JWT admin) o programado (`x-cron-secret`) |
| GET | `/rest/v1/backups?order=started_at.desc` | Historial de backups (admin) |

## 4.11 Errores

| Código | Significado | Mensaje en la app |
|---|---|---|
| `23P01` / `P0409` | Solapamiento de turnos | "El profesional ya tiene un turno en ese horario." |
| `23505` | Duplicado (p. ej. DNI) | "Ya existe un cliente con ese DNI." |
| `42501` | RLS denegó la operación | "No tenés permisos para realizar esta acción." |
| `P0001` | Regla de negocio (`raise exception`) | Se muestra el mensaje de la base |
| `401` | Token vencido | Refresh automático del SDK; si falla, vuelve al login |

## 4.12 Tiempo real

```dart
supabase.channel('agenda')
  .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'appointments',
                     callback: (_) => ref.invalidate(agendaProvider))
  .subscribe();
```
