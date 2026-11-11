import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../payments/presentation/payment_sheet.dart';
import '../../domain/entities/appointment.dart';
import '../agenda_providers.dart';
import '../widgets/appointment_tile.dart';

Future<void> showAppointmentDetail(BuildContext context, String id) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) => _AppointmentDetail(id: id, controller: controller),
      ),
    );

class _AppointmentDetail extends ConsumerWidget {
  const _AppointmentDetail({required this.id, required this.controller});
  final String id;
  final ScrollController controller;

  void _refresh(WidgetRef ref) {
    ref.invalidate(appointmentProvider(id));
    ref.invalidate(agendaProvider);
    ref.invalidate(todayAppointmentsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final appt = ref.watch(appointmentProvider(id));

    return AsyncValueView(
      value: appt,
      onRetry: () => ref.invalidate(appointmentProvider(id)),
      data: (a) {
        final t = Theme.of(context);
        final repo = ref.read(appointmentRepositoryProvider);

        Future<void> run(Future<void> Function() action, String ok) async {
          try {
            await action();
            _refresh(ref);
            if (context.mounted) context.showSnack(ok);
          } catch (e) {
            if (context.mounted) context.showError(e);
          }
        }

        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Row(
              children: [
                Expanded(child: Text(a.serviceName, style: t.textTheme.headlineSmall)),
                StatusChip(a.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('${Fmt.longDate(a.startsAt)} · ${Fmt.timeRange(a.startsAt, a.endsAt)}',
                style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            if (a.rescheduleCount > 0)
              Text('Reprogramado ${a.rescheduleCount} ${a.rescheduleCount == 1 ? 'vez' : 'veces'}',
                  style: t.textTheme.labelSmall),
            const SizedBox(height: 16),

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: InitialsAvatar(initials: Fmt.initials(a.clientName)),
                    title: Text(a.clientName),
                    subtitle: a.clientPhone == null ? null : Text(a.clientPhone!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (a.clientPhone != null)
                          IconButton(
                            tooltip: 'WhatsApp',
                            icon: const Icon(Icons.chat_rounded),
                            onPressed: () => _openWhatsApp(a),
                          ),
                        IconButton(
                          tooltip: 'Ver ficha',
                          icon: const Icon(Icons.badge_outlined),
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/clientes/${a.clientId}');
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.person_pin_rounded, color: a.accent),
                    title: Text(a.therapistName),
                    subtitle: const Text('Profesional'),
                  ),
                  if (user.canViewRevenue) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(Fmt.money(a.finalPrice)),
                      subtitle: Text(a.discountAmount > 0
                          ? 'Precio ${Fmt.money(a.price)} − desc. ${Fmt.money(a.discountAmount)}'
                          : 'Precio del turno'),
                      trailing: a.isPaid
                          ? const Chip(label: Text('Pagado'), avatar: Icon(Icons.check, size: 16))
                          : Text('Saldo ${Fmt.money(a.balance)}',
                              style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
            if (a.notes != null) ...[
              const SectionTitle('Notas'),
              Text(a.notes!),
            ],
            if (a.cancellationReason != null) ...[
              const SectionTitle('Motivo de cancelación'),
              Text(a.cancellationReason!),
            ],

            // ------------------------------------------------ Acciones de estado
            if (a.status.nextStates.isNotEmpty) ...[
              const SectionTitle('Cambiar estado'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in a.status.nextStates)
                    ActionChip(
                      avatar: Icon(s.icon, color: s.color, size: 18),
                      label: Text(s == AppointmentStatus.confirmed
                          ? 'Confirmar asistencia'
                          : s == AppointmentStatus.completed
                              ? 'Marcar completado'
                              : s == AppointmentStatus.noShow
                                  ? 'Marcar ausente'
                                  : 'Volver a pendiente'),
                      onPressed: () => run(() => repo.setStatus(a.id, s), 'Estado: ${s.label}'),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 20),
            if (user.canRegisterPayments && !a.isPaid && a.status != AppointmentStatus.cancelled)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.icon(
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: Text('Registrar pago · ${Fmt.money(a.balance)}'),
                  onPressed: () async {
                    final paid = await showPaymentSheet(context, appointment: a);
                    if (paid == true) _refresh(ref);
                  },
                ),
              ),
            if (user.canCreateAppointments && a.status.isActive) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.update_rounded),
                label: const Text('Reprogramar'),
                onPressed: () => _reschedule(context, ref, a),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: t.colorScheme.error),
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('Cancelar turno'),
                onPressed: () => _cancel(context, ref, a),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openWhatsApp(Appointment a) async {
    final phone = a.clientPhone!.replaceAll(RegExp(r'\D'), '');
    final text = Uri.encodeComponent(
      'Hola ${a.clientName.split(' ').first}, te escribimos por tu turno de ${a.serviceName} '
      'el ${Fmt.shortDate(a.startsAt)} a las ${Fmt.time(a.startsAt)} hs.',
    );
    await launchUrl(Uri.parse('https://wa.me/$phone?text=$text'), mode: LaunchMode.externalApplication);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Appointment a) async {
    final reasons = ['Enfermedad', 'Imprevisto personal', 'Clima', 'Pidió reprogramar', 'No especificado'];
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cancelar turno'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in reasons)
                    ChoiceChip(
                      label: Text(r),
                      selected: controller.text == r,
                      onSelected: (_) => setState(() => controller.text = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Motivo'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
            FilledButton(
              onPressed: controller.text.trim().length < 3 ? null : () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Cancelar turno'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason == null) return;

    try {
      await ref.read(cancelAppointmentProvider)(a, reason);
      _refresh(ref);
      if (!context.mounted) return;
      // Reprogramación automática: ofrecer huecos sugeridos
      final slots = await ref.read(appointmentRepositoryProvider).suggestReschedule(a.id);
      if (!context.mounted) return;
      if (slots.isEmpty) {
        context.showSnack('Turno cancelado');
        return;
      }
      final pick = await showModalBottomSheet<TimeSlot>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Turno cancelado'),
                subtitle: Text('¿Querés ofrecerle uno de estos horarios libres?'),
              ),
              for (final s in slots)
                ListTile(
                  leading: const Icon(Icons.event_available_rounded),
                  title: Text('${Fmt.shortDate(s.start)} · ${Fmt.time(s.start)}'),
                  subtitle: Text(s.therapistName),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (pick != null && context.mounted) {
        await ref.read(createAppointmentProvider)(NewAppointment(
          clientId: a.clientId,
          therapistId: pick.therapistId,
          startsAt: pick.start,
          serviceId: a.serviceId,
          price: a.price,
          discountAmount: a.discountAmount,
          notes: 'Reprogramado desde turno cancelado (${reason.toLowerCase()})',
        ));
        _refresh(ref);
        if (context.mounted) context.showSnack('Nuevo turno: ${Fmt.shortDate(pick.start)} ${Fmt.time(pick.start)}');
      }
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, Appointment a) async {
    final date = await showDatePicker(
      context: context,
      initialDate: a.startsAt.isBefore(DateTime.now()) ? DateTime.now() : a.startsAt,
      firstDate: DateTime.now().dateOnly,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Nueva fecha',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(a.startsAt), helpText: 'Nueva hora');
    if (time == null || !context.mounted) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ref.read(rescheduleAppointmentProvider)(a, start, reason: 'Reprogramado desde detalle');
      _refresh(ref);
      if (context.mounted) context.showSnack('Turno reprogramado');
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }
}
