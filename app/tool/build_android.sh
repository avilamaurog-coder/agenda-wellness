#!/usr/bin/env bash
# =============================================================================
# Compila el APK de Agenda Wellness en macOS / Linux.
# Uso (dentro de la carpeta app/):   ./tool/build_android.sh
# Requisitos: Flutter y Android Studio instalados (flutter doctor sin errores en Android).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f env/prod.json ]]; then
  echo "Falta env/prod.json. Copiá env/prod.example.json y completá SUPABASE_URL y SUPABASE_ANON_KEY." >&2
  exit 1
fi
if grep -qE '<project-ref>|<anon key' env/prod.json; then
  echo "env/prod.json todavía tiene valores de ejemplo." >&2
  exit 1
fi

if [[ ! -d android ]]; then
  echo "Generando proyecto Android..."
  flutter create . --platforms=android --org com.agendawellness --project-name agenda_wellness
  rm -f test/widget_test.dart
fi

dart run tool/configure_android.dart
flutter pub get
flutter build apk --release --dart-define-from-file=env/prod.json

cp build/app/outputs/flutter-apk/app-release.apk agenda-wellness.apk
echo
echo "✅ Listo: app/agenda-wellness.apk"
echo "Con el celular conectado por USB (depuración USB activada):  flutter install"
