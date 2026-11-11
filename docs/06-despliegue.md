# 6. Despliegue en producción

Guía paso a paso desde cero hasta tener la app en las tiendas. Tiempo estimado: 1 día de configuración + los tiempos de revisión de Meta (WhatsApp) y de las tiendas.

## 6.0 Requisitos

| Herramienta | Versión |
|---|---|
| Flutter | ≥ 3.29 (canal stable) |
| Supabase CLI | última (`brew install supabase/tap/supabase` o `npm i -g supabase`) |
| Docker | para el entorno local de Supabase |
| Cuenta Supabase | plan **Pro** recomendado en producción (backups diarios + PITR, sin pausa por inactividad) |
| Cuenta Firebase | para push (FCM) |
| Meta Business + WhatsApp Cloud API | para recordatorios por WhatsApp |
| Resend (u otro SMTP) | para emails transaccionales |
| Google Play Console / Apple Developer | para publicar |

## 6.1 Entorno local

```bash
cd agenda-wellness
supabase start                 # levanta Postgres, Auth, Storage, Realtime en Docker
supabase db reset              # aplica migraciones + seed
supabase test db               # corre los tests pgTAP

cd app
cp env/dev.example.json env/dev.json   # pegar la anon key que mostró `supabase start`
flutter pub get
flutter create . --platforms=android,ios --org com.agendawellness   # genera carpetas nativas (solo la 1ª vez)
flutter run --dart-define-from-file=env/dev.json
```

El primer usuario que se registre queda como **Administrador** del centro del seed. En local los emails de confirmación llegan a Inbucket: `http://127.0.0.1:54324`.

> En emulador Android usá `http://10.0.2.2:54321` como `SUPABASE_URL`.

## 6.2 Proyecto Supabase de producción

1. Crear el proyecto en **São Paulo (sa-east-1)** — menor latencia desde Argentina.
2. Vincular y aplicar el esquema:
   ```bash
   supabase login
   supabase link --project-ref <project-ref>
   supabase db push                  # migraciones
   psql "$DATABASE_URL" -f supabase/seed.sql   # datos iniciales (solo la primera vez)
   ```
3. **Database → Extensions:** verificar `pg_cron`, `pg_net`, `btree_gist`, `pg_trgm` habilitadas (la migración las crea; algunos planes requieren activarlas desde el panel).
4. **Vault** (SQL Editor) — secretos que usa pg_cron:
   ```sql
   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
   select vault.create_secret('<cadena-aleatoria-larga>',          'cron_secret');
   ```
5. **Authentication → URL Configuration**
   - Site URL: `agendawellness://auth-callback`
   - Redirect URLs: `agendawellness://auth-callback`
6. **Authentication → Providers → Email:** confirmación de email ON, contraseña segura ON.
7. **Authentication → SMTP:** configurar SMTP propio (Resend: `smtp.resend.com`, puerto 465) para no depender del límite del SMTP de Supabase. Personalizar las plantillas de email en español.
8. **Personalizar el centro:** editar la fila de `centers` (nombre, teléfono, horario) y cargar `therapist_schedules` de cada profesional (necesario para que `available_slots` sugiera horarios).

## 6.3 Edge Functions y secretos

```bash
supabase secrets set \
  CRON_SECRET='<la misma cadena que en Vault>' \
  WHATSAPP_TOKEN='<token permanente de System User>' \
  WHATSAPP_PHONE_NUMBER_ID='<id del número>' \
  WHATSAPP_TEMPLATE_NAME='recordatorio_turno' \
  RESEND_API_KEY='re_…' \
  EMAIL_FROM='Agenda Wellness <turnos@tudominio.com>' \
  FCM_SERVICE_ACCOUNT_JSON="$(cat firebase-service-account.json)" \
  INVITE_REDIRECT_URL='agendawellness://auth-callback'

supabase functions deploy send-reminders --no-verify-jwt
supabase functions deploy invite-user
```

Probar el despachador manualmente:
```bash
curl -X POST https://<ref>.supabase.co/functions/v1/send-reminders -H "x-cron-secret: <CRON_SECRET>"
# → {"processed":0}
```

## 6.4 WhatsApp Cloud API (Meta)

1. Crear app en developers.facebook.com → producto **WhatsApp**.
2. Registrar y verificar el número del centro (no puede estar en uso en la app de WhatsApp común).
3. Verificar el negocio en Meta Business Manager.
4. Crear un **System User** con permiso `whatsapp_business_messaging` y generar un token permanente.
5. Crear la plantilla **`recordatorio_turno`**, categoría *Utilidad*, idioma *Español (ARG)*, cuerpo:
   ```
   {{1}}
   ```
   (Si Meta rechaza una plantilla de solo variable, usar: `Recordatorio de turno: {{1}}`.)
6. Esperar la aprobación (minutos a 24 h).

Costos: Meta cobra por conversación de utilidad iniciada por el negocio; revisar la tarifa vigente para Argentina.

## 6.5 Firebase (push)

```bash
dart pub global activate flutterfire_cli
cd app && flutterfire configure --project=<firebase-project>
```
Esto genera `google-services.json` y `GoogleService-Info.plist` (no se versionan). Para el backend: *Configuración del proyecto → Cuentas de servicio → Generar clave privada* → usar ese JSON en `FCM_SERVICE_ACCOUNT_JSON`. En iOS, subir la **APNs Auth Key** en Firebase y activar *Push Notifications* y *Background Modes → Remote notifications* en Xcode.

## 6.6 Configuración nativa de la app

### Deep link para recuperación de contraseña e invitaciones

**Android** — `android/app/src/main/AndroidManifest.xml`, dentro de la `<activity>` principal:
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="agendawellness" android:host="auth-callback" />
</intent-filter>
```
Y en `<manifest>`: permisos `INTERNET`, `CAMERA`; `android:usesCleartextTraffic="false"` en `<application>`.
Para abrir WhatsApp/teléfono/mail con `url_launcher` en Android 11+, agregar en `<queries>`:
```xml
<queries>
  <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>
  <intent><action android:name="android.intent.action.DIAL" /></intent>
  <intent><action android:name="android.intent.action.SENDTO" /><data android:scheme="mailto" /></intent>
</queries>
```

**iOS** — `ios/Runner/Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLSchemes</key><array><string>agendawellness</string></array>
</dict></array>
<key>NSCameraUsageDescription</key><string>Para tomar fotos de seguimiento de los tratamientos.</string>
<key>NSPhotoLibraryUsageDescription</key><string>Para adjuntar fotos a las fichas e imágenes de servicios.</string>
<key>LSApplicationQueriesSchemes</key><array><string>whatsapp</string><string>tel</string><string>mailto</string></array>
```

### Identidad
- `applicationId` / Bundle ID: `com.agendawellness.app`
- `minSdkVersion 23` (requerido por firebase_messaging)
- iOS deployment target 13.0
- Ícono y splash: `flutter_launcher_icons` y `flutter_native_splash` con el isotipo salvia sobre fondo arena.

## 6.7 Build de producción

```bash
cp env/prod.example.json env/prod.json   # completar con datos reales

# Android (App Bundle firmado)
flutter build appbundle --release \
  --dart-define-from-file=env/prod.json \
  --obfuscate --split-debug-info=build/symbols

# iOS
flutter build ipa --release --dart-define-from-file=env/prod.json
```

Firma Android: crear `upload.jks` con `keytool`, referenciarlo en `android/key.properties` y en `build.gradle` (`signingConfigs.release`). Activar **Play App Signing**.

## 6.8 CI/CD (GitHub Actions)

- **`ci.yml`** (cada PR): formato, `flutter analyze`, tests unitarios, `supabase db reset` + tests pgTAP.
- **`deploy.yml`** (tag `v*`): `supabase db push` + deploy de funciones → AAB a Google Play (track *internal*) → IPA a TestFlight.

Secretos del repositorio (environment *production*):

| Secreto | Contenido |
|---|---|
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF` | CLI de Supabase |
| `ENV_PROD_JSON` | contenido de `env/prod.json` |
| `GOOGLE_SERVICES_JSON`, `GOOGLE_SERVICE_INFO_PLIST` | Firebase |
| `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` | firma |
| `PLAY_SERVICE_ACCOUNT_JSON` | publicación en Play |
| `APPSTORE_ISSUER_ID`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_PRIVATE_KEY` | TestFlight |

## 6.9 Publicación en tiendas

- **Política de privacidad** publicada (obligatoria: la app maneja datos de salud). Declarar en Play *Data safety* y en App Store *Privacy Nutrition Label*: datos de salud y contacto de terceros (clientes), cifrados en tránsito, no compartidos.
- Indicar que es una app **para uso interno del negocio** con cuenta requerida; dar a los revisores un usuario demo con rol Recepcionista.
- Registrar la base de datos ante la **AAIP** (Ley 25.326) si corresponde.

## 6.10 Operación

| Tema | Recomendación |
|---|---|
| Backups | Plan Pro: diarios + PITR. Exportar mensualmente `pg_dump` a un bucket externo |
| Monitoreo | Supabase → Logs (API, Auth, Edge Functions). Revisar `appointment_reminders` con `status = 'failed'` |
| Errores de la app | Integrar Sentry o Firebase Crashlytics en `runZonedGuarded` de `main.dart` |
| Rendimiento | *Database → Query Performance*; los índices por `(center_id, starts_at)` cubren la agenda |
| Seguridad | *Advisors → Security* de Supabase sin alertas; rotar `CRON_SECRET` y tokens cada 6 meses |
| Migraciones | Siempre nuevas migraciones (nunca editar las aplicadas): `supabase migration new <nombre>` |

### Consultas útiles

```sql
-- Recordatorios fallidos de la última semana
select r.*, a.starts_at from appointment_reminders r join appointments a on a.id = r.appointment_id
where r.status = 'failed' and r.scheduled_for > now() - interval '7 days';

-- Estado de los jobs programados
select jobname, schedule, active from cron.job;
select * from cron.job_run_details order by start_time desc limit 20;
```

## 6.11 Checklist de salida a producción

- [ ] Migraciones aplicadas y seed cargado
- [ ] Datos del centro y horarios de profesionales cargados
- [ ] Precios reales cargados (los del seed son de ejemplo)
- [ ] Vault (`project_url`, `cron_secret`) y secretos de funciones configurados
- [ ] Plantilla de WhatsApp aprobada y probada con un número propio
- [ ] Email de prueba recibido (y no en spam: SPF/DKIM del dominio en Resend)
- [ ] Push recibido en Android e iOS
- [ ] Deep link de recuperación de contraseña probado
- [ ] Tests pgTAP en verde contra la base de staging
- [ ] Usuario admin real creado; usuarios de prueba eliminados
- [ ] Política de privacidad publicada
- [ ] Backups verificados (restaurar una vez en staging)
