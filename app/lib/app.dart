import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/presentation/auth_providers.dart';

class AgendaWellnessApp extends ConsumerStatefulWidget {
  const AgendaWellnessApp({super.key});

  @override
  ConsumerState<AgendaWellnessApp> createState() => _AgendaWellnessAppState();
}

class _AgendaWellnessAppState extends ConsumerState<AgendaWellnessApp> {
  @override
  void initState() {
    super.initState();
    // Navegación al tocar una notificación push
    PushService.instance.taps.listen((data) {
      final route = data['route'];
      if (route is String) ref.read(routerProvider).push(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Al iniciar sesión, registrar el dispositivo para push
    ref.listen(currentUserProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user != null && prev?.valueOrNull?.id != user.id) {
        PushService.instance.registerToken(ref.read(supabaseClientProvider));
      }
    });

    return MaterialApp.router(
      title: 'Agenda Wellness',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
