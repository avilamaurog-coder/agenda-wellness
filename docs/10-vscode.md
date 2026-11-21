# 10. Compilar desde Visual Studio Code

El repositorio trae la carpeta `.vscode/` con todo configurado: ejecutar con **F5**, compilar con **Ctrl+Shift+B** y el resto de las acciones desde **Terminal › Ejecutar tarea…**.

## Requisitos (una sola vez)

1. **Flutter** — [docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows). Descomprimir por ejemplo en `C:\flutter` y agregar `C:\flutter\bin` al `PATH`.
2. **Android Studio** — instalarlo una vez para que descargue el Android SDK. Después, en *SDK Manager › SDK Tools*, marcar **Android SDK Command-line Tools**.
3. **Git** — [git-scm.com](https://git-scm.com).
4. En una terminal: `flutter doctor --android-licenses` (aceptar todo) y `flutter doctor` (Android sin errores).
5. **VS Code** — al abrir el proyecto ofrece instalar las extensiones recomendadas (**Flutter**, **Dart** y **Deno**): aceptar.

## Primera vez

1. **Archivo › Abrir carpeta…** → elegir la carpeta raíz del repositorio (la que contiene `app/`, `supabase/` y `.vscode/`), por ejemplo `D:\IA\PROYECTO X`.
2. **Terminal › Ejecutar tarea… › 1. Preparar proyecto (primera vez)**
   Genera `android/` y `web/`, configura Android, crea `app/env/dev.json` y `app/env/prod.json` y descarga dependencias.
3. Abrir `app/env/prod.json` y completar `SUPABASE_URL` y `SUPABASE_ANON_KEY` (Supabase › Settings › API). Hacer lo mismo con `dev.json` si usás un backend local.

## Uso diario

| Quiero… | Cómo |
|---|---|
| Ejecutar la app con recarga en caliente | Elegir dispositivo abajo a la derecha (celular por USB, emulador, Chrome) → **F5** → *App (desarrollo)* o *App (producción, depuración)* |
| Compilar el APK | **Ctrl+Shift+B** → queda en `app/build/app/outputs/flutter-apk/app-release.apk` |
| Instalar el APK en el celular | Tarea **3. Instalar APK en el celular (USB)** (con depuración USB activada) |
| Compilar la web | Tarea **4. Compilar web** → `app/build/web/` |
| App Bundle para Play Store | Tarea **5. Compilar App Bundle** (requiere la firma configurada, ver [06-despliegue](06-despliegue.md)) |
| Analizar / tests | Tareas **Analizar código** y **Tests** |
| Algo raro después de actualizar | Tarea **Limpiar compilación** y después **1. Preparar proyecto** |

## Problemas frecuentes

- **`flutter` no se reconoce** — falta `C:\flutter\bin` en el `PATH`; cerrar y volver a abrir VS Code después de agregarlo.
- **"No supported devices connected"** — activar *Opciones de desarrollador › Depuración USB* en el celular y aceptar el aviso en pantalla, o elegir *Chrome* como dispositivo.
- **La app dice "Falta configurar el servidor"** — `app/env/*.json` todavía tiene los valores de ejemplo.
- **Gradle falla con `429 Too Many Requests`** — Maven Central limitó las descargas: volver a compilar; lo ya descargado queda en caché.
- Más casos en [08-compilar-android](08-compilar-android.md#problemas-frecuentes).
