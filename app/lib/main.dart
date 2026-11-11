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
    Env.validate();

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
