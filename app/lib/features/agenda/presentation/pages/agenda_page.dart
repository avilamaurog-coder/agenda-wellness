import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/entities/appointment.dart';
import '../agenda_providers.dart';
import '../widgets/timeline_grid.dart';
import 'appointment_detail_sheet.dart';
import 'appointment_form_sheet.dart';

final _showCancelledProvider = StateProvider<bool>((ref) => false);

class AgendaPage extends ConsumerWidget {
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final filter = ref.watch(agendaFilterProvider);
    final notifier = ref.read(agendaFilterProvider.notifier);

    final title = switch (filter.view) {
      AgendaView.day => Fmt.longDate(filter.date),
      AgendaView.week =>
        'Semana del ${filter.date.startOfWeek.day} de ${Fmt.monthYear(filter.date.startOfWeek)}',
      AgendaView.month => Fmt.monthYear(filter.date),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(tooltip: 'Hoy', icon: const Icon(Icons.today_rounded), onPressed: notifier.today),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'cancelled',
                checked: ref.read(_showCancelledProvider),
                child: const Text('Mostrar cancelados'),
              ),
            ],
            onSelected: (_) => ref.read(_showCancelledProvider.notifier).update((v) => !v),
          ),
        ],
      ),
      floatingActionButton: user.canCreateAppointments
          ? FloatingActionButton.extended(
              onPressed: () => showAppointmentForm(context, initialStart: _defaultStart(filter.date)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Turno'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => notifier.shift(-1)),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: filter.date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) notifier.setDate(d);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => notifier.shift(1)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AgendaView>(
              segments: const [
                ButtonSegment(value: AgendaView.day, label: Text('Día'), icon: Icon(Icons.view_day_outlined)),
                ButtonSegment(value: AgendaView.week, label: Text('Semana'), icon: Icon(Icons.view_week_outlined)),
                ButtonSegment(value: AgendaView.month, label: Text('Mes'), icon: Icon(Icons.calendar_view_month)),
              ],
              selected: {filter.view},
              onSelectionChanged: (s) => notifier.setView(s.first),
            ),
          ),
          if (user.isFrontDesk) const _TherapistFilter(),
          const SizedBox(height: 8),
          const Expanded(child: _AgendaBody()),
        ],
      ),
    );
  }

  static DateTime _defaultStart(DateTime date) {
    final now = DateTime.now();
    if (date.isSameDay(now)) {
      final m = ((now.minute / 15).ceil() * 15);
      return DateTime(now.year, now.month, now.day, now.hour).add(Duration(minutes: m));
    }
    return DateTime(date.year, date.month, date.day, 10);
  }
}

class _TherapistFilter extends ConsumerWidget {
  const _TherapistFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final therapists = ref.watch(therapistsProvider).valueOrNull ?? const <AppUser>[];
    final selected = ref.watch(agendaFilterProvider).therapistId;
    if (therapists.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          FilterChip(
            label: const Text('Todos'),
            selected: selected == null,
            onSelected: (_) => ref.read(agendaFilterProvider.notifier).setTherapist(null),
          ),
          for (final t in therapists) ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: CircleAvatar(backgroundColor: t.color, radius: 6),
              label: Text(t.fullName.split(' ').first),
              selected: selected == t.id,
              onSelected: (_) => ref.read(agendaFilterProvider.notifier).setTherapist(t.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgendaBody extends ConsumerWidget {
  const _AgendaBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(agendaFilterProvider);
    final appts = ref.watch(agendaProvider);
    final showCancelled = ref.watch(_showCancelledProvider);
    final user = ref.watch(sessionUserProvider);
    final therapists = ref.watch(therapistsProvider).valueOrNull ?? const <AppUser>[];

    return AsyncValueView(
      value: appts,
      onRetry: () => ref.invalidate(agendaProvider),
      data: (all) {
        final list = showCancelled ? all : all.where((a) => a.status != AppointmentStatus.cancelled).toList();

        Future<void> onMove(Appointment a, DateTime start, String? therapistId) async {
          if (start == a.startsAt && (therapistId == null || therapistId == a.therapistId)) return;
          final ok = await context.confirm(
            'Reprogramar turno',
            '${a.clientName}\n${Fmt.shortDate(a.startsAt)} ${Fmt.time(a.startsAt)}  →  '
                '${Fmt.shortDate(start)} ${Fmt.time(start)}',
            ok: 'Reprogramar',
          );
          if (!ok) return;
          try {
            await ref.read(agendaProvider.notifier).move(a, start, therapistId: therapistId);
            if (context.mounted) context.showSnack('Turno reprogramado. Se reenviarán los recordatorios.');
          } catch (e) {
            if (context.mounted) context.showError(e);
          }
        }

        void onTapEmpty(DateTime start, String? therapistId) {
          if (!user.canCreateAppointments) return;
          showAppointmentForm(context, initialStart: start, therapistId: therapistId ?? filter.therapistId);
        }

        void onTap(Appointment a) => showAppointmentDetail(context, a.id);
        final canMove = user.canCreateAppointments ? onMove : null;

        switch (filter.view) {
          case AgendaView.day:
            final visible = filter.therapistId == null
                ? therapists
                : therapists.where((t) => t.id == filter.therapistId).toList();
            final columns = visible.isEmpty
                ? [TimelineColumn(title: 'Turnos', date: filter.date, appointments: list)]
                : [
                    for (final t in visible)
                      TimelineColumn(
                        title: t.fullName,
                        subtitle: '${list.where((a) => a.therapistId == t.id && a.status.isActive).length} turnos',
                        date: filter.date,
                        therapistId: t.id,
                        color: t.color,
                        appointments: list.where((a) => a.therapistId == t.id).toList(),
                      ),
                  ];
            return TimelineGrid(columns: columns, onTapAppointment: onTap, onMove: canMove, onTapEmpty: onTapEmpty);

          case AgendaView.week:
            final start = filter.date.startOfWeek;
            final today = DateTime.now();
            final columns = [
              for (var i = 0; i < 7; i++)
                () {
                  final d = start.add(Duration(days: i));
                  return TimelineColumn(
                    title: Fmt.shortDate(d),
                    date: d,
                    highlight: d.isSameDay(today),
                    appointments: list.where((a) => a.startsAt.isSameDay(d)).toList(),
                  );
                }(),
            ];
            return TimelineGrid(
              columns: columns,
              minColumnWidth: 120,
              pixelsPerMinute: 1.1,
              onTapAppointment: onTap,
              onMove: canMove,
              onTapEmpty: onTapEmpty,
            );

          case AgendaView.month:
            return _MonthView(appointments: list);
        }
      },
    );
  }
}

class _MonthView extends ConsumerWidget {
  const _MonthView({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(agendaFilterProvider);
    final t = Theme.of(context);
    final byDay = <DateTime, List<Appointment>>{};
    for (final a in appointments) {
      byDay.putIfAbsent(a.startsAt.dateOnly, () => []).add(a);
    }
    final selectedList = byDay[filter.date.dateOnly] ?? const [];

    return Column(
      children: [
        TableCalendar<Appointment>(
          locale: 'es_AR',
          firstDay: DateTime(2020),
          lastDay: DateTime(2100),
          focusedDay: filter.date,
          selectedDayPredicate: (d) => d.isSameDay(filter.date),
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerVisible: false,
          availableGestures: AvailableGestures.horizontalSwipe,
          eventLoader: (d) => byDay[d.dateOnly] ?? const [],
          onDaySelected: (d, _) => ref.read(agendaFilterProvider.notifier).setDate(d),
          onPageChanged: (d) => ref.read(agendaFilterProvider.notifier).setDate(d),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(color: t.colorScheme.secondaryContainer, shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: t.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w700),
            selectedDecoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle),
            outsideDaysVisible: false,
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in events.take(4))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: e.status.color, shape: BoxShape.circle),
                      ),
                    if (events.length > 4)
                      Text('+${events.length - 4}', style: const TextStyle(fontSize: 9)),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text(Fmt.longDate(filter.date), style: t.textTheme.titleSmall)),
              TextButton(
                onPressed: () => ref.read(agendaFilterProvider.notifier).setView(AgendaView.day),
                child: const Text('Ver día'),
              ),
            ],
          ),
        ),
        Expanded(
          child: selectedList.isEmpty
              ? const EmptyState(icon: Icons.event_available_outlined, title: 'Sin turnos este día')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: selectedList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = selectedList[i];
                    return ListTile(
                      tileColor: t.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Icon(a.status.icon, color: a.status.color),
                      title: Text(a.clientName),
                      subtitle: Text('${Fmt.timeRange(a.startsAt, a.endsAt)} · ${a.serviceName}'),
                      onTap: () => showAppointmentDetail(context, a.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
