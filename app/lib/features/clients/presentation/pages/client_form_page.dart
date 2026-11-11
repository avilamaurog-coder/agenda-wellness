import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../domain/entities/client.dart';
import '../clients_providers.dart';

/// Alta y edición de clientes. Al crear, hace `pop(Client)` para que quien
/// la abrió (p. ej. el selector de clientes del turno) reciba el nuevo registro.
class ClientFormPage extends ConsumerStatefulWidget {
  const ClientFormPage({super.key, this.clientId});
  final String? clientId;

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'first', 'last', 'dni', 'phone', 'whatsapp', 'email', 'address',
      'observations', 'allergies', 'contraindications', 'internal',
    ])
      k: TextEditingController(),
  };
  DateTime? _birth;
  bool _acceptsReminders = true;
  bool _sameAsPhone = true;
  NotificationChannel _channel = NotificationChannel.whatsapp;
  bool _saving = false;
  bool _loaded = false;
  Client? _original;

  bool get _editing => widget.clientId != null;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Client c) {
    if (_loaded) return;
    _loaded = true;
    _original = c;
    _c['first']!.text = c.firstName;
    _c['last']!.text = c.lastName;
    _c['dni']!.text = c.dni ?? '';
    _c['phone']!.text = c.phone ?? '';
    _c['whatsapp']!.text = c.whatsapp ?? '';
    _c['email']!.text = c.email ?? '';
    _c['address']!.text = c.address ?? '';
    _c['observations']!.text = c.observations ?? '';
    _c['allergies']!.text = c.allergies ?? '';
    _c['contraindications']!.text = c.contraindications ?? '';
    _c['internal']!.text = c.internalNotes ?? '';
    _birth = c.birthDate;
    _acceptsReminders = c.acceptsReminders;
    _channel = c.preferredChannel;
    _sameAsPhone = (c.whatsapp ?? '') == (c.phone ?? '');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(clientRepositoryProvider);
    final draft = Client(
      id: widget.clientId,
      firstName: _c['first']!.text,
      lastName: _c['last']!.text,
      dni: _c['dni']!.text,
      phone: _c['phone']!.text,
      whatsapp: _sameAsPhone ? _c['phone']!.text : _c['whatsapp']!.text,
      email: _c['email']!.text,
      birthDate: _birth,
      address: _c['address']!.text,
      observations: _c['observations']!.text,
      allergies: _c['allergies']!.text,
      contraindications: _c['contraindications']!.text,
      internalNotes: _c['internal']!.text,
      acceptsReminders: _acceptsReminders,
      preferredChannel: _channel,
      createdAt: _original?.createdAt,
    );
    try {
      final saved = _editing ? await repo.update(draft) : await repo.create(draft);
      refreshClient(ref, saved.id!);
      if (mounted) {
        context.showSnack(_editing ? 'Cliente actualizado' : 'Cliente creado');
        context.pop(saved);
      }
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing && !_loaded) {
      final async = ref.watch(clientProvider(widget.clientId!));
      return Scaffold(
        appBar: AppBar(title: const Text('Editar cliente')),
        body: AsyncValueView(
          value: async,
          data: (c) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _fill(c));
            });
            return const Center(child: CircularProgressIndicator());
          },
        ),
      );
    }

    const gap = SizedBox(height: 12);
    InputDecoration dec(String label, [IconData? icon]) =>
        InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon));

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar cliente' : 'Nuevo cliente'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            const SectionTitle('Datos personales'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _c['first'],
                    textCapitalization: TextCapitalization.words,
                    decoration: dec('Nombre *'),
                    validator: (v) => Validators.required(v, 'El nombre'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _c['last'],
                    textCapitalization: TextCapitalization.words,
                    decoration: dec('Apellido *'),
                    validator: (v) => Validators.required(v, 'El apellido'),
                  ),
                ),
              ],
            ),
            gap,
            TextFormField(
              controller: _c['dni'],
              keyboardType: TextInputType.number,
              decoration: dec('DNI', Icons.badge_outlined),
              validator: Validators.dni,
            ),
            gap,
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _birth ?? DateTime(1990),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                  initialEntryMode: DatePickerEntryMode.input,
                  helpText: 'Fecha de nacimiento',
                );
                if (d != null) setState(() => _birth = d);
              },
              child: InputDecorator(
                decoration: dec('Fecha de nacimiento', Icons.cake_outlined),
                child: Text(_birth == null ? '—' : Fmt.date(_birth!)),
              ),
            ),
            gap,
            TextFormField(controller: _c['address'], decoration: dec('Dirección', Icons.home_outlined)),

            const SectionTitle('Contacto'),
            TextFormField(
              controller: _c['phone'],
              keyboardType: TextInputType.phone,
              decoration: dec('Teléfono', Icons.phone_outlined),
              validator: Validators.phone,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sameAsPhone,
              title: const Text('El WhatsApp es el mismo número'),
              onChanged: (v) => setState(() => _sameAsPhone = v ?? true),
            ),
            if (!_sameAsPhone) ...[
              TextFormField(
                controller: _c['whatsapp'],
                keyboardType: TextInputType.phone,
                decoration: dec('WhatsApp', Icons.chat_outlined),
                validator: Validators.phone,
              ),
              gap,
            ],
            TextFormField(
              controller: _c['email'],
              keyboardType: TextInputType.emailAddress,
              decoration: dec('Email', Icons.mail_outline),
              validator: (v) => Validators.email(v, optional: true),
            ),

            const SectionTitle('Recordatorios'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _acceptsReminders,
              title: const Text('Acepta recordatorios automáticos'),
              onChanged: (v) => setState(() => _acceptsReminders = v),
            ),
            if (_acceptsReminders)
              SegmentedButton<NotificationChannel>(
                segments: const [
                  ButtonSegment(value: NotificationChannel.whatsapp, label: Text('WhatsApp'), icon: Icon(Icons.chat)),
                  ButtonSegment(value: NotificationChannel.email, label: Text('Email'), icon: Icon(Icons.mail)),
                  ButtonSegment(value: NotificationChannel.telegram, label: Text('Telegram'), icon: Icon(Icons.send)),
                ],
                selected: {_channel == NotificationChannel.push ? NotificationChannel.whatsapp : _channel},
                onSelectionChanged: (s) => setState(() => _channel = s.first),
              ),

            const SectionTitle('Salud'),
            TextFormField(
              controller: _c['allergies'],
              maxLines: 2,
              decoration: dec('Alergias', Icons.warning_amber_rounded),
            ),
            gap,
            TextFormField(
              controller: _c['contraindications'],
              maxLines: 2,
              decoration: dec('Contraindicaciones', Icons.health_and_safety_outlined),
            ),
            gap,
            TextFormField(controller: _c['observations'], maxLines: 3, decoration: dec('Observaciones')),

            const SectionTitle('Interno'),
            TextFormField(
              controller: _c['internal'],
              maxLines: 3,
              decoration: dec('Notas internas (no visibles para el cliente)', Icons.lock_outline),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar cliente')),
          ],
        ),
      ),
    );
  }
}
