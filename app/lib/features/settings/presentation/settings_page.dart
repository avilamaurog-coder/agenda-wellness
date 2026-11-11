import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: InitialsAvatar(initials: Fmt.initials(user.fullName), color: user.color, radius: 26),
              title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${user.role.label} · ${user.email}'),
            ),
          ),
          const SectionTitle('Gestión'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notificaciones'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/mas/notificaciones'),
                ),
                if (user.canViewRevenue)
                  ListTile(
                    leading: const Icon(Icons.insert_chart_outlined_rounded),
                    title: const Text('Reportes'),
                    subtitle: const Text('Ventas, turnos, servicios, clientes · PDF y Excel'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/mas/reportes'),
                  ),
                if (user.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Datos del centro'),
                    subtitle: const Text('Logo, contacto, Telegram y catálogo público'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/mas/centro'),
                  ),
                if (user.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Copias de seguridad'),
                    subtitle: const Text('Backup diario en Google Drive / OneDrive'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/mas/backups'),
                  ),
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Ver catálogo público'),
                  subtitle: const Text('Lo que ven tus clientes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/catalogo'),
                ),
                if (user.canManageUsers)
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Equipo y permisos'),
                    subtitle: const Text('Invitar, aprobar y asignar roles'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/mas/equipo'),
                  ),
              ],
            ),
          ),
          const SectionTitle('Apariencia'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Auto')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
            onPressed: () async {
              final ok = await context.confirm('Cerrar sesión', '¿Querés salir de tu cuenta?', ok: 'Salir');
              if (ok) await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: 16),
          Center(child: Text('Agenda Wellness · v1.0.0', style: Theme.of(context).textTheme.labelSmall)),
        ],
      ),
    );
  }
}
