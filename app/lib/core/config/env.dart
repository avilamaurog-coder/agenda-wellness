import 'package:flutter/foundation.dart';

/// Configuración inyectada en compilación con `--dart-define-from-file=env/<entorno>.json`.
///
/// Nunca se incluyen secretos de servidor (service_role, tokens de WhatsApp, etc.):
/// la app solo conoce la URL pública y la anon key, y la seguridad la garantiza RLS.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const environment = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static const authRedirect = String.fromEnvironment(
    'AUTH_REDIRECT',
    defaultValue: 'agendawellness://auth-callback',
  );
  static const enablePush = bool.fromEnvironment('ENABLE_PUSH', defaultValue: false);

  /// URL pública del catálogo (versión web), p. ej. https://agenda.tucentro.com/catalogo
  static const publicCatalogUrl = String.fromEnvironment('PUBLIC_CATALOG_URL');

  static bool get isProduction => environment == 'prod';

  /// En web, los enlaces de email (recuperación, invitación) vuelven al mismo sitio.
  static String get redirectUrl => kIsWeb ? Uri.base.origin : authRedirect;

  /// Enlace al catálogo: el configurado, o el del propio sitio cuando corre en web.
  static String get catalogUrl =>
      publicCatalogUrl.isNotEmpty ? publicCatalogUrl : (kIsWeb ? '${Uri.base.origin}/catalogo' : '');

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Faltan SUPABASE_URL / SUPABASE_ANON_KEY. '
        'Ejecutá: flutter run --dart-define-from-file=env/dev.json',
      );
    }
  }
}
