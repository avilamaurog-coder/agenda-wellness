# 🌿 Agenda Wellness

Aplicación móvil (Android + iOS) y **web para administradores** para la gestión integral de centros de estética, bienestar y masoterapia: clientes, agenda con arrastrar y soltar, servicios y precios, cobros, historia clínica, recordatorios automáticos por WhatsApp/email/push/**Telegram** (con confirmación desde el chat), **vitrina de servicios y productos con catálogo público**, **logo del centro**, **backups diarios cifrados en Google Drive / OneDrive**, dashboard y reportes PDF/Excel.

**Stack:** Flutter · Riverpod · Clean Architecture · Supabase (PostgreSQL, Auth, Storage, Realtime, Edge Functions) · Firebase Cloud Messaging.

## Inicio rápido

```bash
# 1. Backend local
supabase start && supabase db reset

# 2. App
cd app
cp env/dev.example.json env/dev.json        # pegar la anon key de `supabase start`
flutter create . --platforms=android,ios --org com.agendawellness   # solo la 1ª vez
flutter create . --platforms=web             # versión web para administradores (opcional)
rm -f test/widget_test.dart                  # test de ejemplo que genera flutter create
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

Registrate en la app: el **primer usuario** queda como Administrador. Para deep links, permisos y push, seguí la [guía de despliegue](docs/06-despliegue.md#66-configuración-nativa-de-la-app).

## Panel web de administración

`admin-web/` es un panel liviano para el administrador: **usuarios** (aprobar, roles, invitar, horarios) y **agenda** (día/semana, arrastrar para reprogramar, crear, cancelar, cobrar). Probalo sin backend abriendo `admin-web/index.html?demo=1`. Se publica solo en GitHub Pages ([detalle](docs/09-panel-web.md)).

## Instalar en Android

- **Sin instalar nada:** subí el proyecto a un repo privado de GitHub, cargá los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY`, y ejecutá *Actions › Compilar APK Android*.
- **En tu PC (Windows):** `cd app` → completar `env\prod.json` → `.\tool\build_android.ps1`.
- **En Visual Studio Code:** abrir la carpeta del repo → tarea *1. Preparar proyecto* → completar `app/env/prod.json` → **Ctrl+Shift+B**. Ver [docs/10-vscode.md](docs/10-vscode.md).

Detalle en [docs/08-compilar-android.md](docs/08-compilar-android.md).

## Documentación

| # | Documento | Contenido |
|---|---|---|
| 1 | [Análisis funcional](docs/01-analisis-funcional.md) | Roles, matriz de permisos, casos de uso, reglas de negocio, requisitos no funcionales, roadmap |
| 2 | [Arquitectura](docs/02-arquitectura.md) | Diagrama, decisiones, Clean Architecture, seguridad, pipeline de recordatorios, estructura de carpetas |
| 3 | [Modelo de datos](docs/03-modelo-datos.md) | Diagrama ER, diccionario, vistas, RPC, triggers, jobs |
| 4 | [APIs REST](docs/04-api.md) | Endpoints, ejemplos, errores, tiempo real |
| 5 | [UX/UI y wireframes](docs/05-ux-ui-wireframes.md) | Sistema de diseño, mapa de navegación, wireframes de cada pantalla |
| 6 | [Despliegue](docs/06-despliegue.md) | Supabase, WhatsApp, Firebase, configuración nativa, build, CI/CD, tiendas, checklist |
| 7 | [Telegram, web, backups, logo y vitrina](docs/07-telegram-web-backups-vitrina.md) | Bot y confirmaciones, web solo admin, Google Drive/OneDrive, restauración, catálogo público |
| 8 | [Compilar e instalar en Android](docs/08-compilar-android.md) | APK en GitHub Actions o en tu PC, instalación en el celular, problemas frecuentes |
| 9 | [Panel web de administración](docs/09-panel-web.md) | Usuarios y agenda desde la computadora, modo demo, publicación en GitHub Pages |
| 10 | [Visual Studio Code](docs/10-vscode.md) | Abrir, ejecutar (F5) y compilar APK/web desde VS Code |

## Qué incluye el código

| Entregable | Ubicación |
|---|---|
| Esquema PostgreSQL completo (21 tablas, enums, índices, restricción anti-solapamiento) | `supabase/migrations/…0001_schema.sql` |
| Triggers: perfiles y roles, precios, bitácora, recordatorios, auditoría | `…0002_functions_triggers.sql` |
| Row Level Security por rol en todas las tablas | `…0003_rls.sql` |
| RPC de agenda, disponibilidad, dashboard y reportes | `…0004_rpc_reports.sql` |
| Buckets de Storage, Realtime y jobs pg_cron | `…0005_storage_cron_realtime.sql` |
| Datos iniciales: 11 servicios, 3 categorías, 2 combos, plantillas | `supabase/seed.sql` |
| Edge Functions: recordatorios (WhatsApp/Resend/FCM) e invitaciones | `supabase/functions/` |
| Tests de base de datos (pgTAP) | `supabase/tests/` |
| Autenticación: login, registro, recuperación, aprobación, invitaciones | `app/lib/features/auth/` |
| CRUD de clientes + historial + historia clínica con fotos | `app/lib/features/clients/` |
| CRUD de servicios + historial de precios + combos | `app/lib/features/services/` |
| Agenda día/semana/mes con drag & drop, disponibilidad y reprogramación automática | `app/lib/features/agenda/` |
| Cobros | `app/lib/features/payments/` |
| Dashboard gerencial con gráficos | `app/lib/features/dashboard/` |
| Reportes con exportación PDF y Excel | `app/lib/features/reports/` |
| Equipo, notificaciones en tiempo real, modo claro/oscuro | `app/lib/features/settings/` |
| Telegram: vinculación, recordatorios con botones, confirmación/cancelación, canal de promociones | `supabase/functions/telegram-*` |
| Backup diario cifrado a Google Drive u OneDrive + script de restauración | `supabase/functions/backup`, `supabase/scripts/` |
| Datos del centro, logo y copias de seguridad | `app/lib/features/center/` |
| Vitrina: productos, promociones y catálogo público `/catalogo` | `app/lib/features/showcase/` |
| Web de administración (Firebase Hosting) | `app/firebase.json` |
| Tests unitarios | `app/test/` |
| CI y despliegue (Play Store, TestFlight, Supabase) | `.github/workflows/` |

## Pendiente para la próxima iteración

- Pantallas de alta/edición de **combos** y de **promociones con código de descuento** (esquema, RLS y seed ya listos; la vitrina de promociones publicitarias ya está implementada).
- Pantalla para editar **plantillas de recordatorio** y **horarios laborales** desde la app (hoy desde Supabase Studio).
- Confirmación de turnos respondiendo "SI" por WhatsApp (webhook de Meta; por Telegram ya funciona con botones).
- Venta de productos con descuento de stock desde la caja.
- Cobro online con Mercado Pago Checkout Pro.

## Licencia

Privado — todos los derechos reservados.
