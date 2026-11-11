import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../clients/domain/entities/client.dart';
import '../../../clients/presentation/widgets/client_picker.dart';
import '../../../services/domain/service.dart';
import '../../../services/presentation/services_providers.dart';
import '../../domain/entities/appointment.dart';
import '../agenda_providers.dart';

Future<Appointment?> showAppointmentForm(
  BuildContext context, {
  DateTime? initialStart,
  String? therapistId,
  Client? client,
}) =>
    showModalBottomSheet<Appointment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: AppointmentFormSheet(initialStart: initialStart, therapistId: therapistId, client: client),
      ),
    );

class AppointmentFormSheet extends ConsumerStatefulWidget {
  const AppointmentFormSheet({super.key, this.initialStart, this.therapistId, this.client});
  final DateTime? initialStart;
  final String? therapistId;
  final Client? client;

  @override
  ConsumerState<AppointmentFormSheet> createState() => _AppointmentFormSheetState();
}

class _AppointmentFormSheetState extends ConsumerState<AppointmentFormSheet> {
  Client? _client;
  Service? _service;
  Combo? _combo;
  String? _therapistId;
  late DateTime _date;
  TimeOfDay? _time;
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  bool _confirmed = false;
  bool _saving = false;
  bool _useCombo = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _therapistId = widget.therapistId;
    final s = widget.initialStart ?? DateTime.now();
    _date = s.dateOnly;
    if (widget.initialStart != null) _time = TimeOfDay.fromDateTime(s);
  }

  @override
  void dispose() {
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? get _start =>
      _time == null ? null : DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);

  num get _basePrice => _useCombo ? (_combo?.price ?? 0) : (_service?.effectivePrice ?? 0);
  num get _discountValue => Validators.parseMoney(_discount.text) ?? 0;

  bool get _valid =>
      _client != null && (_useCombo ? _combo != null : _service != null) && _therapistId != null && _start != null;

  Future<void> _save() async {
    if (!_valid) return;
    if (_discountValue > _basePrice) {
      context.showSnack('El descuento supera el precio', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await ref.read(createAppointmentProvider)(
            NewAppointment(
              clientId: _client!.id!,
              therapistId: _therapistId!,
              startsAt: _start!,
              serviceId: _useCombo ? null : _service!.id,
              comboId: _useCombo ? _combo!.id : null,
              durationMinutes: _useCombo ? _combo!.totalMinutes : null,
              price: _basePrice,
              discountAmount: _discountValue,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              confirmed: _confirmed,
            ),
          );
      ref.invalidate(agendaProvider);
      ref.invalidate(todayAppointmentsProvider);
      if (mounted) {
        Navigator.pop(context, created);
        context.showSnack('Turno agendado para ${Fmt.shortDate(created.startsAt)} a las ${Fmt.time(created.startsAt)}');
      }
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final services = ref.watch(activeServicesProvider).valueOrNull ?? const <Service>[];
    final combos = (ref.watch(combosProvider).valueOrNull ?? const <Combo>[]).where((c) => c.isActive).toList();
    final allTherapists = ref.watch(therapistsProvider).valueOrNull ?? const <AppUser>[];
    final therapists = (!_useCombo && _service != null && _service!.therapistIds.isNotEmpty)
        ? allTherapists.where((x) => _service!.therapistIds.contains(x.id)).toList()
        : allTherapists;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text('Nuevo turno'),
        actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // ------------------------------------------------ Cliente
          const SectionTitle('Cliente'),
          Card(
            child: ListTile(
              leading: Icon(_client == null ? Icons.person_search_rounded : Icons.person_rounded),
              title: Text(_client?.fullName ?? 'Seleccionar cliente'),
              subtitle: _client == null ? null : Text(_client!.whatsapp ?? _client!.phone ?? _client!.email ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final c = await showClientPicker(context);
                if (c != null) setState(() => _client = c);
              },
            ),
          ),
          if (_client?.hasHealthAlerts ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: Colors.orange.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const Icon(Icons.health_and_safety_rounded, color: Colors.orange),
                  title: const Text('Atención'),
                  subtitle: Text([
                    if (_client!.allergies?.isNotEmpty ?? false) 'Alergias: ${_client!.allergies}',
                    if (_client!.contraindications?.isNotEmpty ?? false) 'Contraindicaciones: ${_client!.contraindications}',
                  ].join('\n')),
                ),
              ),
            ),

          // ------------------------------------------------ Servicio / combo
          SectionTitle(
            'Servicio',
            trailing: combos.isEmpty
                ? null
                : SegmentedButton<bool>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Servicio')),
                      ButtonSegment(value: true, label: Text('Combo')),
                    ],
                    selected: {_useCombo},
                    onSelectionChanged: (s) => setState(() {
                      _useCombo = s.first;
                      _time = null;
                    }),
                  ),
          ),
          if (!_useCombo)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in services)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                    label: Text('${s.name} · ${Fmt.duration(s.durationMinutes)}'),
                    selected: _service?.id == s.id,
                    onSelected: (_) => setState(() {
                      _service = s;
                      if (_therapistId != null && s.therapistIds.isNotEmpty && !s.therapistIds.contains(_therapistId)) {
                        _therapistId = null;
                      }
                    }),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final c in combos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: _combo?.id == c.id ? t.colorScheme.primary : Colors.transparent, width: 2),
                      ),
                      child: ListTile(
                        title: Text(c.name),
                        subtitle: Text('${c.services.map((s) => s.name).join(' + ')}\n${Fmt.duration(c.totalMinutes)}'),
                        isThreeLine: true,
                        trailing: Text(Fmt.money(c.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => setState(() => _combo = c),
                      ),
                    ),
                  ),
              ],
            ),

          // ------------------------------------------------ Profesional
          const SectionTitle('Profesional'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in therapists)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: p.color, radius: 6),
                  label: Text(p.fullName),
                  selected: _therapistId == p.id,
                  onSelected: (_) => setState(() => _therapistId = p.id),
                ),
            ],
          ),

          // ------------------------------------------------ Fecha y hora
          const SectionTitle('Fecha y hora'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(Fmt.shortDate(_date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().dateOnly,
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(_time == null ? 'Hora' : _time!.format(context)),
                  onPressed: () async {
                    final tm = await showTimePicker(
                      context: context,
                      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (tm != null) setState(() => _time = tm);
                  },
                ),
              ),
            ],
          ),
          if (!_useCombo && _service != null) _SlotSuggestions(
            date: _date,
            serviceId: _service!.id!,
            therapistId: _therapistId,
            selected: _start,
            onPick: (slot) => setState(() {
              _time = TimeOfDay.fromDateTime(slot.start);
              _therapistId = slot.therapistId;
            }),
          ),

          // ------------------------------------------------ Precio y notas
          const SectionTitle('Precio'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Precio')),
                      if (!_useCombo && (_service?.hasActivePromo ?? false))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(Fmt.money(_service!.price),
                              style: const TextStyle(decoration: TextDecoration.lineThrough)),
                        ),
                      Text(Fmt.money(_basePrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Descuento', prefixText: r'$ '),
                    onChanged: (_) => setState(() {}),
                  ),
                  const Divider(height: 28),
                  Row(
                    children: [
                      Text('Total', style: t.textTheme.titleMedium),
                      const Spacer(),
                      Text(Fmt.money((_basePrice - _discountValue).clamp(0, double.infinity)),
                          style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas del turno (opcional)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            title: const Text('Marcar como confirmado'),
            subtitle: const Text('El cliente ya confirmó su asistencia'),
            onChanged: (v) => setState(() => _confirmed = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _valid && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: const Text('Agendar turno'),
          ),
        ],
      ),
    );
  }
}

class _SlotSuggestions extends ConsumerWidget {
  const _SlotSuggestions({
    required this.date,
    required this.serviceId,
    required this.therapistId,
    required this.selected,
    required this.onPick,
  });

  final DateTime date;
  final String serviceId;
  final String? therapistId;
  final DateTime? selected;
  final void Function(TimeSlot) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(availableSlotsProvider((date: date, serviceId: serviceId, therapistId: therapistId)));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: slots.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => const SizedBox.shrink(),
        data: (list) {
          if (list.isEmpty) {
            return Text(
              'No hay horarios libres cargados para este día. Podés elegir la hora manualmente.',
              style: Theme.of(context).textTheme.bodySmall,
            );
          }
          // Un chip por horario (se agrupa por hora de inicio si hay varios profesionales)
          final seen = <DateTime>{};
          final unique = list.where((s) => seen.add(s.start)).take(24).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Horarios disponibles', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in unique)
                    ChoiceChip(
                      label: Text(Fmt.time(s.start)),
                      tooltip: s.therapistName,
                      selected: selected == s.start,
                      onSelected: (_) => onPick(s),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
