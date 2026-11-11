import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/notifications/push_service.dart';
import 'core/theme/theme_mode_provider.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    usePathUrlStrategy(); // web: URLs limpias (/catalogo) en lugar de /#/catalogo

    // Sin URL/clave de Supabase la app no puede funcionar: se explica en pantalla en vez de cerrarse.
    if (Env.supabaseUrl.isEmpty || Env.supabaseAnonKey.isEmpty) {
      runApp(const _MissingConfigApp());
      return;
    }

    await initializeDateFormatting('es_AR');
    final prefs = await SharedPreferences.getInstance();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
      debug: !Env.isProduction,
    );

    await PushService.instance.init();

    runApp(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const AgendaWellnessApp(),
      ),
    );
  }, (error, stack) {
    // Punto de integración para Sentry/Crashlytics en producción.
    debugPrint('Error no controlado: $error\n$stack');
  });
}

/// Pantalla que se muestra cuando el APK se compiló sin SUPABASE_URL / SUPABASE_ANON_KEY.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF5E7D6F)),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_rounded, size: 64, color: Color(0xFF5E7D6F)),
                  SizedBox(height: 16),
                  Text('Agenda Wellness', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12),
                  Text(
                    'Falta configurar el servidor.\n\n'
                    'Cargá los secretos SUPABASE_URL y SUPABASE_ANON_KEY en GitHub '
                    '(Settings › Secrets and variables › Actions) y volvé a compilar el APK.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
