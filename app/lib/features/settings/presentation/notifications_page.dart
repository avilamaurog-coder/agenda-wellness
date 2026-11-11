import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../agenda/presentation/pages/appointment_detail_sheet.dart';

class InternalNotification {
  const InternalNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body,
    this.payload = const {},
    this.readAt,
  });

  final String id;
  final String kind;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  IconData get icon => switch (kind) {
        'upcoming_appointment' => Icons.alarm_rounded,
        'new_client' => Icons.person_add_alt_rounded,
        'cancellation' => Icons.event_busy_rounded,
        'pending_payment' => Icons.receipt_long_rounded,
        'client_confirmation' => Icons.verified_rounded,
        'reschedule_request' => Icons.update_rounded,
        'backup' => Icons.cloud_off_rounded,
        _ => Icons.info_outline_rounded,
      };

  factory InternalNotification.fromJson(Map<String, dynamic> j) => InternalNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        payload: (j['payload'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        readAt: DateTime.tryParse(j['read_at'] as String? ?? ''),
      );
}

/// Campana en tiempo real (Supabase Realtime sobre `internal_notifications`).
final notificationsProvider = StreamProvider.autoDispose<List<InternalNotification>>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .from('internal_notifications')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(InternalNotification.fromJson).toList()); // más recientes primero
});

final unreadCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => n.readAt == null).length ?? 0,
);

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _markAllRead(WidgetRef ref) => ref
      .read(supabaseClientProvider)
      .from('internal_notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .isFilter('read_at', null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(onPressed: () => _markAllRead(ref), child: const Text('Marcar leídas')),
        ],
      ),
      body: AsyncValueView(
        value: items,
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.notifications_none_rounded, title: 'Todo al día')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final n = list[i];
                  return ListTile(
                    tileColor: n.readAt == null ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
                    leading: CircleAvatar(child: Icon(n.icon)),
                    title: Text(n.title, style: TextStyle(fontWeight: n.readAt == null ? FontWeight.w700 : null)),
                    subtitle: Text([n.body, '${Fmt.shortDate(n.createdAt)} ${Fmt.time(n.createdAt)}']
                        .whereType<String>()
                        .join('\n')),
                    onTap: () async {
                      await ref
                          .read(supabaseClientProvider)
                          .from('internal_notifications')
                          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
                          .eq('id', n.id);
                      final apptId = n.payload['appointment_id'];
                      if (apptId is String && context.mounted) await showAppointmentDetail(context, apptId);
                    },
                  );
                },
              ),
      ),
    );
  }
}
