import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/auth_providers.dart';

/// Todo el staff, incluidos usuarios pendientes de aprobación (inactivos).
final _allStaffProvider = FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final rows = await ref.watch(supabaseClientProvider).from('profiles').select().order('is_active').order('full_name');
  return rows.map(AppUser.fromJson).toList();
});

class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionUserProvider);
    final staff = ref.watch(_allStaffProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Equipo y permisos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Invitar'),
      ),
      body: AsyncValueView(
        value: staff,
        onRetry: () => ref.invalidate(_allStaffProvider),
        data: (list) {
          final pending = list.where((u) => !u.isActive).toList();
          final active = list.where((u) => u.isActive).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              if (pending.isNotEmpty) ...[
                const SectionTitle('Pendientes de aprobación'),
                for (final u in pending) _UserTile(user: u, isMe: false),
              ],
              const SectionTitle('Activos'),
              for (final u in active) _UserTile(user: u, isMe: u.id == me.id),
            ],
          );
        },
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController();
    final email = TextEditingController();
    var role = UserRole.therapist;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Invitar al equipo'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => Validators.required(v, 'El nombre'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (r) => setState(() => role = r ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Enviar invitación'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await ref.read(authRepositoryProvider).inviteUser(email: email.text, fullName: name.text, role: role);
        ref.invalidate(_allStaffProvider);
        if (context.mounted) context.showSnack('Invitación enviada a ${email.text}');
      } catch (e) {
        if (context.mounted) context.showError(e);
      }
    }
    name.dispose();
    email.dispose();
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, required this.isMe});
  final AppUser user;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> update(UserRole role, bool active) async {
      try {
        await ref.read(authRepositoryProvider).updateUserRole(user.id, role, active: active);
        ref.invalidate(_allStaffProvider);
        ref.invalidate(therapistsProvider);
      } catch (e) {
        if (context.mounted) context.showError(e);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: InitialsAvatar(initials: Fmt.initials(user.fullName), color: user.color),
        title: Text(isMe ? '${user.fullName} (vos)' : user.fullName),
        subtitle: Text('${user.role.label} · ${user.email}'),
        trailing: isMe
            ? null
            : !user.isActive
                ? FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => update(user.role, true),
                    child: const Text('Aprobar'),
                  )
                : PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      for (final r in UserRole.values)
                        CheckedPopupMenuItem(value: r.value, checked: r == user.role, child: Text(r.label)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'disable', child: Text('Desactivar acceso')),
                    ],
                    onSelected: (v) => v == 'disable' ? update(user.role, false) : update(UserRole.parse(v), true),
                  ),
      ),
    );
  }
}
