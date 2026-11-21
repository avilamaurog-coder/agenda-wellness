// =============================================================================
// Prepara el proyecto para compilar (la primera vez, o después de clonar).
//
// Uso (desde la carpeta app/):   dart run tool/setup.dart
// En VS Code:                    Terminal › Ejecutar tarea › "1. Preparar proyecto"
//
// Es idempotente: se puede correr varias veces.
//   1. Genera las carpetas android/ y web/ con `flutter create` si no existen
//   2. Borra el test de ejemplo que crea `flutter create`
//   3. Aplica la configuración de Android (tool/configure_android.dart)
//   4. Crea env/dev.json y env/prod.json a partir de los .example.json
//   5. Descarga las dependencias (flutter pub get)
// =============================================================================
import 'dart:io';

Future<void> main() async {
  final appDir = File(Platform.script.toFilePath()).parent.parent;
  Directory.current = appDir;

  final platforms = [
    if (!Directory('android').existsSync()) 'android',
    if (!Directory('web').existsSync()) 'web',
  ];
  if (platforms.isNotEmpty) {
    _title('Generando plataformas: ${platforms.join(', ')}');
    await _run('flutter', [
      'create',
      '.',
      '--platforms=${platforms.join(',')}',
      '--org',
      'com.agendawellness',
      '--project-name',
      'agenda_wellness',
    ]);
  } else {
    _title('Plataformas android/ y web/ ya generadas');
  }

  final sampleTest = File('test/widget_test.dart');
  if (sampleTest.existsSync()) sampleTest.deleteSync();

  _title('Configurando Android');
  await _run('dart', ['run', 'tool/configure_android.dart']);

  _title('Archivos de configuración');
  var pending = false;
  for (final env in ['dev', 'prod']) {
    final target = File('env/$env.json');
    if (!target.existsSync()) {
      File('env/$env.example.json').copySync(target.path);
      stdout.writeln('  Creado env/$env.json (copia del ejemplo)');
    }
    if (target.readAsStringSync().contains('<')) {
      stdout.writeln('  ⚠ env/$env.json todavía tiene valores de ejemplo: '
          'completá SUPABASE_URL y SUPABASE_ANON_KEY');
      pending = true;
    } else {
      stdout.writeln('  ✓ env/$env.json');
    }
  }

  _title('Descargando dependencias');
  await _run('flutter', ['pub', 'get']);

  stdout.writeln('');
  stdout.writeln('✅ Proyecto listo.');
  if (pending) {
    stdout.writeln('   Falta completar env/*.json; sin eso la app muestra '
        '"Falta configurar el servidor".');
  }
}

void _title(String text) => stdout.writeln('\n▶ $text');

Future<void> _run(String exe, List<String> args) async {
  // runInShell: en Windows `flutter` es un .bat y necesita el shell.
  final process = await Process.start(exe, args,
      runInShell: true, mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('✗ Falló: $exe ${args.join(' ')} (código $code)');
    exit(code);
  }
}
