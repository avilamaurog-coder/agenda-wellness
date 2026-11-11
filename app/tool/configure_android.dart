// =============================================================================
// Configura el proyecto Android generado por `flutter create` para Agenda Wellness.
//
// Uso (desde la carpeta app/):   dart run tool/configure_android.dart
//
// Es idempotente: se puede correr varias veces sin duplicar cambios.
//   * Nombre visible "Agenda Wellness" e ID de aplicación com.agendawellness.app
//   * minSdk 23 (requerido por Firebase Messaging)
//   * Permisos de internet y cámara
//   * Deep link agendawellness://auth-callback (recuperar contraseña, invitaciones)
//   * <queries> para abrir WhatsApp, teléfono y email (Android 11+)
// =============================================================================
import 'dart:io';

const appName = 'Agenda Wellness';
const applicationId = 'com.agendawellness.app';
const minSdk = 23;

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('No existe android/. Ejecutá primero: '
        'flutter create . --platforms=android --org com.agendawellness --project-name agenda_wellness');
    exit(1);
  }

  _patchManifest(manifest);

  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (kts.existsSync()) {
    _patchGradle(kts, kotlin: true);
  } else if (groovy.existsSync()) {
    _patchGradle(groovy, kotlin: false);
  } else {
    stderr.writeln('No se encontró android/app/build.gradle(.kts)');
    exit(1);
  }

  stdout.writeln('✅ Android configurado: $appName ($applicationId), minSdk $minSdk');
}

void _patchManifest(File file) {
  var xml = file.readAsStringSync();

  // 1. Permisos
  const permissions = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
  ];
  final missing = permissions.where((p) => !xml.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final start = xml.indexOf('<manifest');
    final end = xml.indexOf('>', start) + 1;
    final lines = missing.map((p) => '\n    <uses-permission android:name="$p" />').join();
    xml = xml.substring(0, end) + lines + xml.substring(end);
  }

  // 2. Nombre visible
  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="$appName"');

  // 3. Sin tráfico HTTP en claro
  if (!xml.contains('usesCleartextTraffic')) {
    xml = xml.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="false"');
  }

  // 4. Deep link para recuperación de contraseña e invitaciones
  if (!xml.contains('android:scheme="agendawellness"')) {
    const deepLink = '''<intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="agendawellness" android:host="auth-callback" />
            </intent-filter>
        </activity>''';
    xml = xml.replaceFirst('</activity>', deepLink);
  }

  // 5. Apps externas que abre url_launcher (WhatsApp, teléfono, email, mapas)
  if (!xml.contains('android.intent.action.DIAL')) {
    const intents = '''
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="mailto" />
        </intent>''';
    if (xml.contains('<queries>')) {
      xml = xml.replaceFirst('<queries>', '<queries>$intents');
    } else {
      xml = xml.replaceFirst('</manifest>', '    <queries>$intents\n    </queries>\n</manifest>');
    }
  }

  file.writeAsStringSync(xml);
}

void _patchGradle(File file, {required bool kotlin}) {
  var g = file.readAsStringSync();
  if (kotlin) {
    g = g.replaceAll(RegExp(r'minSdk\s*=\s*[^\n]+'), 'minSdk = $minSdk');
    g = g.replaceAll(RegExp(r'applicationId\s*=\s*"[^"]*"'), 'applicationId = "$applicationId"');
  } else {
    g = g.replaceAll(RegExp(r'minSdkVersion\s+[^\n]+'), 'minSdkVersion $minSdk');
    g = g.replaceAll(RegExp(r'applicationId\s+"[^"]*"'), 'applicationId "$applicationId"');
  }
  file.writeAsStringSync(g);
}
