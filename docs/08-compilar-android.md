# 8. Compilar e instalar en Android

El resultado es un **APK** que se instala directamente en el celular (sin pasar por Play Store). Para publicar en la tienda, ver el job `android` de `deploy.yml` y la [guía de despliegue](06-despliegue.md).

## Paso 0 — Backend en la nube (obligatorio antes de compilar)

La app se conecta a Supabase y **no puede apuntar a `localhost`** desde un celular. Necesitás un proyecto en la nube:

1. Crear proyecto en supabase.com (región **São Paulo**).
2. Desde la carpeta del proyecto:
   ```bash
   supabase login
   supabase link --project-ref <project-ref>
   supabase db push
   psql "<connection string de Settings › Database>" -f supabase/seed.sql
   ```
3. En **Settings › API** copiar:
   - *Project URL* → `SUPABASE_URL`
   - *anon public key* → `SUPABASE_ANON_KEY`
4. En **Authentication › URL Configuration** agregar `agendawellness://auth-callback` a *Redirect URLs*.

> La anon key es pública por diseño (va dentro de la app); la seguridad la da RLS. **Nunca** uses la `service_role` en la app.

---

## Opción A — Compilar en GitHub (sin instalar nada en tu PC)

1. Crear un repositorio **privado** en GitHub y subir la carpeta `agenda-wellness` completa.
2. En el repo: **Settings › Secrets and variables › Actions › New repository secret**:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. **Actions › Compilar APK Android › Run workflow**.
4. Esperar ~8–10 minutos. Al terminar, abrir la ejecución y descargar **agenda-wellness-apk** en *Artifacts* (es un .zip con el APK adentro).

Si en el futuro creás un tag `v1.0.1`, el APK también se adjunta automáticamente en **Releases**.

---

## Opción B — Compilar en tu computadora (Windows)

**Instalación (una sola vez, ~30 min):**
1. Instalar **Android Studio** (developer.android.com/studio). Abrirlo una vez y dejar que descargue el SDK. En *More Actions › SDK Manager › SDK Tools* marcar **Android SDK Command-line Tools**.
2. Instalar **Flutter** (docs.flutter.dev/get-started/install/windows) y agregar `flutter\bin` al PATH.
3. En una terminal:
   ```powershell
   flutter doctor --android-licenses   # aceptar todo con "y"
   flutter doctor                      # la línea de Android debe quedar con ✓
   ```

**Compilar:**
```powershell
cd agenda-wellness\app
copy env\prod.example.json env\prod.json
notepad env\prod.json                # pegar SUPABASE_URL y SUPABASE_ANON_KEY
.\tool\build_android.ps1
```
Si PowerShell bloquea el script: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

El APK queda en `app\agenda-wellness.apk`. En macOS/Linux el equivalente es `./tool/build_android.sh`.

El script hace todo solo: genera la carpeta `android/` la primera vez, aplica la configuración (nombre, ID `com.agendawellness.app`, permisos, deep link, minSdk 23) con `tool/configure_android.dart`, descarga dependencias y compila.

---

## Instalar en el celular

**Por USB (más rápido):** activar *Opciones de desarrollador* (tocar 7 veces "Número de compilación" en *Ajustes › Acerca del teléfono*) → activar **Depuración USB** → conectar y ejecutar `flutter install` desde `app\`.

**Copiando el archivo:** pasar el APK por WhatsApp, Drive o cable → abrirlo en el celular → permitir **Instalar apps desconocidas** para esa aplicación cuando lo pida → Instalar.

Al abrir por primera vez, **registrate**: el primer usuario queda como Administrador.

---

## Problemas frecuentes

| Síntoma | Solución |
|---|---|
| La app se cierra al abrir | `env/prod.json` vacío o con valores de ejemplo. Revisar URL y anon key y recompilar |
| "Sin conexión" al iniciar sesión | La URL apunta a `localhost`/`127.0.0.1`; usar la del proyecto en la nube |
| No llega el email de confirmación | Revisar spam; configurar SMTP propio en Supabase (ver guía de despliegue) |
| El enlace de "olvidé mi contraseña" no abre la app | Falta `agendawellness://auth-callback` en *Redirect URLs* de Supabase |
| `flutter doctor` marca licencias | `flutter doctor --android-licenses` |
| Error de compilación de Dart | El código se escribió sin poder compilarlo en el entorno de generación: copiá el error completo del log (o del paso *Análisis estático* en GitHub) y se corrige |
| "App no instalada" | Desinstalar una versión anterior firmada con otra clave e instalar de nuevo |

## Notas

- El APK de esta guía va **firmado con la clave de depuración**: sirve para instalar y usar, no para Play Store. Para la tienda se usa la clave de subida (`ANDROID_KEYSTORE_*` en `deploy.yml`) y `flutter build appbundle`.
- Las **notificaciones push** quedan desactivadas (`ENABLE_PUSH: false`) hasta configurar Firebase (`flutterfire configure`). Los recordatorios por WhatsApp, email y Telegram no dependen de esto.
- Para cambiar el ícono: agregar `flutter_launcher_icons` con el logo del centro y ejecutar `dart run flutter_launcher_icons`.
