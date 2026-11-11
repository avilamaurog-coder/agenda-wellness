import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../agenda/presentation/agenda_providers.dart';
import '../../../agenda/presentation/pages/appointment_form_sheet.dart';
import '../../../agenda/presentation/widgets/appointment_tile.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/entities/client.dart';
import '../clients_providers.dart';
import '../widgets/telegram_link_card.dart';
import 'clinical_record_sheet.dart';

class ClientDetailPage extends ConsumerWidget {
  const ClientDetailPage({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final client = ref.watch(clientProvider(clientId));

    final tabs = <(String, Widget)>[
      ('Resumen', _SummaryTab(clientId: clientId)),
      ('Turnos', _AppointmentsTab(clientId: clientId)),
      if (user.canViewClinical) ('Ficha clínica', _ClinicalTab(clientId: clientId)),
      if (user.canViewRevenue) ('Pagos', _PaymentsTab(clientId: clientId)),
    ];

    return AsyncValueView(
      value: client,
      onRetry: () => ref.invalidate(clientProvider(clientId)),
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (c) => DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(c.fullName),
            actions: [
              if (user.canManageClients)
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push('/clientes/$clientId/editar'),
                ),
              if (user.canDeleteClients)
                PopupMenuButton<String>(
                  itemBuilder: (_) => const [PopupMenuItem(value: 'archive', child: Text('Archivar cliente'))],
                  onSelected: (_) async {
                    final ok = await context.confirm(
                      'Archivar cliente',
                      'El cliente dejará de aparecer en búsquedas. Su historial y pagos se conservan.',
                      ok: 'Archivar',
                      destructive: true,
                    );
                    if (!ok) return;
                    try {
                      await ref.read(clientRepositoryProvider).archive(clientId);
                      ref.invalidate(clientListProvider);
                      if (context.mounted) context.pop();
                    } catch (e) {
                      if (context.mounted) context.showError(e);
                    }
                  },
                ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: t.$1)],
            ),
          ),
          floatingActionButton: user.canCreateAppointments
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await showAppointmentForm(context, client: c);
                    ref.invalidate(clientAppointmentsProvider(clientId));
                    ref.invalidate(clientStatsProvider(clientId));
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: const Text('Agendar'),
                )
              : null,
          body: TabBarView(children: [for (final t in tabs) t.$2]),
        ),
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final c = ref.watch(clientProvider(clientId)).requireValue;
    final stats = ref.watch(clientStatsProvider(clientId));
    final t = Theme.of(context);

    Widget info(IconData icon, String label, String? value, {VoidCallback? onTap}) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : ListTile(
            dense: true,
            leading: Icon(icon),
            title: Text(value),
            subtitle: Text(label),
            onTap: onTap,
            trailing: onTap == null ? null : const Icon(Icons.open_in_new, size: 18),
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (c.hasHealthAlerts)
          Card(
            color: Colors.orange.withValues(alpha: 0.12),
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_rounded, color: Colors.orange),
              title: const Text('Alertas de salud'),
              subtitle: Text([
                if (c.allergies?.isNotEmpty ?? false) 'Alergias: ${c.allergies}',
                if (c.contraindications?.isNotEmpty ?? false) 'Contraindicaciones: ${c.contraindications}',
              ].join('\n')),
            ),
          ),
        const SizedBox(height: 12),
        AsyncValueView<ClientStats>(
          value: stats,
          loading: const SizedBox(height: 90, child: LoadingList(items: 1)),
          data: (s) => Row(
            children: [
              _Stat(label: 'Asistencias', value: '${s.attended}'),
              _Stat(label: 'Cancelados', value: '${s.cancelled}'),
              _Stat(label: 'Ausencias', value: '${s.noShows}'),
              if (user.canViewRevenue) _Stat(label: 'Gastado', value: Fmt.compactMoney(s.totalSpent)),
            ],
          ),
        ),
        if (stats.valueOrNull?.nextVisit != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Próximo turno: ${Fmt.shortDate(stats.value!.nextVisit!)} ${Fmt.time(stats.value!.nextVisit!)}',
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
        const SectionTitle('Telegram'),
        TelegramLinkCard(client: c, canManage: user.canManageClients),
        const SectionTitle('Contacto'),
        Card(
          child: Column(
            children: [
              info(Icons.chat_outlined, 'WhatsApp', c.whatsapp, onTap: c.whatsapp == null ? null : () {
                launchUrl(Uri.parse('https://wa.me/${c.whatsapp!.replaceAll(RegExp(r'\D'), '')}'),
                    mode: LaunchMode.externalApplication);
              }),
              info(Icons.phone_outlined, 'Teléfono', c.phone, onTap: c.phone == null ? null : () {
                launchUrl(Uri.parse('tel:${c.phone}'));
              }),
              info(Icons.mail_outline, 'Email', c.email, onTap: c.email == null ? null : () {
                launchUrl(Uri.parse('mailto:${c.email}'));
              }),
              info(Icons.home_outlined, 'Dirección', c.address),
            ],
          ),
        ),
        const SectionTitle('Datos'),
        Card(
          child: Column(
            children: [
              info(Icons.badge_outlined, 'DNI', c.dni),
              info(Icons.cake_outlined, 'Nacimiento',
                  c.birthDate == null ? null : '${Fmt.date(c.birthDate!)} (${c.age} años)'),
              info(Icons.notifications_active_outlined, 'Recordatorios',
                  c.acceptsReminders ? 'Sí, por ${c.preferredChannel.label}' : 'No desea recibir'),
            ],
          ),
        ),
        if ((c.observations ?? '').isNotEmpty) ...[
          const SectionTitle('Observaciones'),
          Text(c.observations!),
        ],
        if (user.canManageClients && (c.internalNotes ?? '').isNotEmpty) ...[
          const SectionTitle('Notas internas'),
          Text(c.internalNotes!),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              FittedBox(child: Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              Text(label, style: t.textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentsTab extends ConsumerWidget {
  const _AppointmentsTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView(
      value: ref.watch(clientAppointmentsProvider(clientId)),
      onRetry: () => ref.invalidate(clientAppointmentsProvider(clientId)),
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Icons.event_note_outlined, title: 'Sin turnos registrados')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => AppointmentTile(appointment: list[i], showDate: true, showClient: false),
            ),
    );
  }
}

class _ClinicalTab extends ConsumerWidget {
  const _ClinicalTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(clinicalRecordsProvider(clientId));
    return Stack(
      children: [
        AsyncValueView(
          value: records,
          onRetry: () => ref.invalidate(clinicalRecordsProvider(clientId)),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'Sin evaluaciones',
                  message: 'Registrá la primera evaluación para hacer seguimiento de la evolución.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _RecordCard(record: list[i]),
                ),
        ),
        Positioned(
          left: 16,
          bottom: 88,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () async {
              final saved = await showClinicalRecordSheet(context, clientId: clientId);
              if (saved == true) ref.invalidate(clinicalRecordsProvider(clientId));
            },
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Nueva evaluación'),
          ),
        ),
      ],
    );
  }
}

class _RecordCard extends ConsumerWidget {
  const _RecordCard({required this.record});
  final ClinicalRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    final t = Theme.of(context);
    Widget block(String title, String? text) => (text == null || text.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary)),
                Text(text),
              ],
            ),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(Fmt.date(r.recordDate), style: t.textTheme.titleMedium)),
                if (r.painScale != null) Chip(label: Text('Dolor ${r.painScale}/10')),
              ],
            ),
            if (r.therapistName != null) Text(r.therapistName!, style: t.textTheme.bodySmall),
            block('Evaluación', r.evaluation),
            block('Objetivos del tratamiento', r.treatmentGoals),
            block('Evolución', r.evolution),
            block('Observaciones', r.observations),
            if (r.photoPaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.photoPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _SignedPhoto(path: r.photoPaths[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Las fotos clínicas viven en un bucket privado: se muestran con URL firmada temporal.
final _signedUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(clientRepositoryProvider).signedPhotoUrl(path),
);

class _SignedPhoto extends ConsumerWidget {
  const _SignedPhoto({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(_signedUrlProvider(path));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 84,
        child: url.when(
          loading: () => const ColoredBox(color: Colors.black12),
          error: (_, __) => const Icon(Icons.broken_image_outlined),
          data: (u) => GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: u, cacheKey: path))),
            ),
            child: CachedNetworkImage(imageUrl: u, cacheKey: path, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView(
      value: ref.watch(clientPaymentsProvider(clientId)),
      data: (list) {
        if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sin pagos registrados');
        final total = list.where((p) => p.status == 'paid').fold<num>(0, (s, p) => s + p.amount);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: ListTile(
                title: const Text('Total abonado'),
                trailing: Text(Fmt.money(total), style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: 8),
            for (final p in list)
              ListTile(
                leading: Icon(p.method.icon),
                title: Text(Fmt.money(p.amount)),
                subtitle: Text('${p.method.label} · ${p.paidAt == null ? '' : Fmt.date(p.paidAt!)}'
                    '${p.reference == null ? '' : ' · ${p.reference}'}'),
                trailing: p.status == 'paid' ? null : Chip(label: Text(p.status)),
              ),
          ],
        );
      },
    );
  }
}
