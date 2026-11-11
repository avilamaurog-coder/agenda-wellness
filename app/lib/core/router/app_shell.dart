import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';

/// Navegación principal: barra inferior en móvil, rail lateral en tablet/escritorio.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _destinations = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Inicio'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Agenda'),
    (Icons.people_outline_rounded, Icons.people_rounded, 'Clientes'),
    (Icons.storefront_outlined, Icons.storefront_rounded, 'Catálogo'),
    (Icons.menu_rounded, Icons.menu_open_rounded, 'Más'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Al cerrar sesión, desmonta las pantallas internas antes de que el router redirija
    // (evita que lean `sessionUserProvider` sin usuario).
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || (kIsWeb && !user.isAdmin)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.spa_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
