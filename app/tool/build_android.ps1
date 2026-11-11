# =============================================================================
# Compila el APK de Agenda Wellness en Windows.
# Uso (PowerShell, dentro de la carpeta app\):   .\tool\build_android.ps1
# Requisitos: Flutter y Android Studio instalados (flutter doctor sin errores en Android).
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path "env\prod.json")) {
    Write-Host "Falta env\prod.json. Copiá env\prod.example.json y completá SUPABASE_URL y SUPABASE_ANON_KEY." -ForegroundColor Red
    exit 1
}
if ((Get-Content "env\prod.json" -Raw) -match "<project-ref>|<anon key") {
    Write-Host "env\prod.json todavía tiene valores de ejemplo. Completalo con los datos de tu proyecto Supabase." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "android")) {
    Write-Host "Generando proyecto Android..." -ForegroundColor Cyan
    flutter create . --platforms=android --org com.agendawellness --project-name agenda_wellness
    if (Test-Path "test\widget_test.dart") { Remove-Item "test\widget_test.dart" }
}

dart run tool/configure_android.dart
flutter pub get
flutter build apk --release --dart-define-from-file=env/prod.json

$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
    Copy-Item $apk "agenda-wellness.apk" -Force
    Write-Host ""
    Write-Host "Listo: app\agenda-wellness.apk" -ForegroundColor Green
    Write-Host "Con el celular conectado por USB (depuración USB activada):  flutter install"
}
