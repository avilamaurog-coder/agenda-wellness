import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/agenda/presentation/pages/agenda_page.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/password_pages.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/clients/presentation/pages/client_detail_page.dart';
import '../../features/clients/presentation/pages/client_form_page.dart';
import '../../features/clients/presentation/pages/clients_page.dart';
import '../../features/center/presentation/backups_page.dart';
import '../../features/center/presentation/center_settings_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/showcase/domain/showcase.dart';
import '../../features/showcase/presentation/catalog_page.dart';
import '../../features/showcase/presentation/post_form_page.dart';
import '../../features/showcase/presentation/product_form_page.dart';
import '../../features/showcase/presentation/public_catalog_page.dart';
import '../../features/settings/presentation/notifications_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/team_page.dart';
import '../../features/services/presentation/pages/service_form_page.dart';
import '../supabase/supabase_providers.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Notifica a GoRouter cuando cambia la sesión para re-evaluar redirecciones.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref<Object?> ref) {
    ref.listen(currentUserProvider, (_, __) => notifyListeners());
    ref.listen(authStateChangesProvider, (_, next) {
      if (next.valueOrNull?.event == AuthChangeEvent.passwordRecovery) {
        recovering = true;
      }
      notifyListeners();
    });
  }
  bool recovering = false;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // Catálogo público: accesible con o sin sesión
      if (state.matchedLocation == '/catalogo') return null;

      final userAsync = ref.read(currentUserProvider);
      if (userAsync.isLoading && !userAsync.hasValue) return '/splash';

      final user = userAsync.valueOrNull;
      final loc = state.matchedLocation;
      final inAuth = loc.startsWith('/auth');

      if (refresh.recovering) {
        if (loc != '/auth/reset') return '/auth/reset';
        refresh.recovering = false;
        return null;
      }
      // En web solo administradores: cualquier otra sesión se trata como no autenticada
      if (user == null || !user.isActive || (kIsWeb && !user.isAdmin)) {
        return inAuth ? null : '/auth/login';
      }
      if (inAuth || loc == '/splash') return '/';

      // Rutas exclusivas de administración
      if (loc.startsWith('/servicios/') && !user.canManageServices) return '/servicios';
      if (loc == '/mas/equipo' && !user.canManageUsers) return '/mas';
      if (loc == '/mas/reportes' && !user.canViewRevenue) return '/mas';
      if ((loc == '/mas/centro' || loc == '/mas/backups') && !user.isAdmin) return '/mas';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/auth/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/auth/forgot', builder: (_, __) => const ForgotPasswordPage()),
      GoRoute(path: '/auth/reset', builder: (_, __) => const ResetPasswordPage()),
      GoRoute(path: '/catalogo', builder: (_, __) => const PublicCatalogPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/agenda', builder: (_, __) => const AgendaPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/clientes',
              builder: (_, __) => const ClientsPage(),
              routes: [
                GoRoute(
                  path: 'nuevo',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const ClientFormPage(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (_, s) => ClientDetailPage(clientId: s.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'editar',
                      parentNavigatorKey: _rootKey,
                      builder: (_, s) => ClientFormPage(clientId: s.pathParameters['id']),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/servicios',
              builder: (_, __) => const CatalogPage(),
              routes: [
                GoRoute(
                  path: 'nuevo',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const ServiceFormPage(),
                ),
                GoRoute(
                  path: 'productos/nuevo',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const ProductFormPage(),
                ),
                GoRoute(
                  path: 'productos/:id',
                  parentNavigatorKey: _rootKey,
                  redirect: (_, s) => s.extra is Product ? null : '/servicios',
                  builder: (_, s) => ProductFormPage(product: s.extra as Product?),
                ),
                GoRoute(
                  path: 'promociones/nueva',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const PostFormPage(),
                ),
                GoRoute(
                  path: 'promociones/:id',
                  parentNavigatorKey: _rootKey,
                  redirect: (_, s) => s.extra is PromoPost ? null : '/servicios',
                  builder: (_, s) => PostFormPage(post: s.extra as PromoPost?),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, s) => ServiceFormPage(serviceId: s.pathParameters['id']),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/mas',
              builder: (_, __) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'notificaciones',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const NotificationsPage(),
                ),
                GoRoute(
                  path: 'reportes',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const ReportsPage(),
                ),
                GoRoute(
                  path: 'equipo',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const TeamPage(),
                ),
                GoRoute(
                  path: 'centro',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const CenterSettingsPage(),
                ),
                GoRoute(
                  path: 'backups',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const BackupsPage(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
