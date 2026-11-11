import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/service.dart';
import '../services_providers.dart';

class ServiceFormPage extends ConsumerStatefulWidget {
  const ServiceFormPage({super.key, this.serviceId});
  final String? serviceId;

  @override
  ConsumerState<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends ConsumerState<ServiceFormPage> {
  static const _palette = [
    '#8FA998', '#A8C3B8', '#6F8F7F', '#9DB4C0', '#C9B79C',
    '#D4A5A5', '#E3B5A4', '#B5A8C9', '#A3A3C2', '#C98B6B',
  ];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController(text: '60');
  final _buffer = TextEditingController(text: '10');
  final _price = TextEditingController();
  final _promo = TextEditingController();
  String? _categoryId;
  String _color = _palette.first;
  DateTime? _promoUntil;
  bool _active = true;
  Set<String> _therapists = {};
  Uint8List? _image;
  String? _imageUrl;
  bool _saving = false;
  bool _loaded = false;

  bool get _editing => widget.serviceId != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _duration, _buffer, _price, _promo]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Service s) {
    _loaded = true;
    _name.text = s.name;
    _description.text = s.description ?? '';
    _duration.text = '${s.durationMinutes}';
    _buffer.text = '${s.bufferMinutes}';
    _price.text = s.price.toStringAsFixed(0);
    _promo.text = s.promoPrice?.toStringAsFixed(0) ?? '';
    _categoryId = s.categoryId;
    _color = s.colorHex ?? _palette.first;
    _promoUntil = s.promoValidUntil;
    _active = s.isActive;
    _therapists = s.therapistIds.toSet();
    _imageUrl = s.imageUrl;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final price = Validators.parseMoney(_price.text)!;
    final promo = Validators.parseMoney(_promo.text);
    if (promo != null && promo >= price) {
      context.showSnack('El precio promocional debe ser menor al precio regular', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(serviceRepositoryProvider).save(
            Service(
              id: widget.serviceId,
              name: _name.text,
              description: _description.text.trim().isEmpty ? null : _description.text,
              categoryId: _categoryId,
              durationMinutes: int.parse(_duration.text),
              bufferMinutes: int.tryParse(_buffer.text) ?? 0,
              price: price,
              promoPrice: promo,
              promoValidUntil: promo == null ? null : _promoUntil,
              colorHex: _color,
              imageUrl: _imageUrl,
              isActive: _active,
              therapistIds: _therapists.toList(),
            ),
            image: _image,
          );
      ref.invalidate(servicesProvider);
      ref.invalidate(combosProvider);
      if (mounted) {
        context.showSnack(_editing ? 'Servicio actualizado' : 'Servicio creado');
        context.pop();
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
      final list = ref.watch(servicesProvider).valueOrNull;
      final s = list?.where((e) => e.id == widget.serviceId).firstOrNull;
      if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      _fill(s);
    }

    final categories = ref.watch(serviceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];
    final therapists = ref.watch(therapistsProvider).valueOrNull ?? const <AppUser>[];
    final t = Theme.of(context);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar servicio' : 'Nuevo servicio'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await context.confirm(
                  'Eliminar servicio',
                  'Dejará de estar disponible. Los turnos e informes históricos se conservan.',
                  ok: 'Eliminar',
                  destructive: true,
                );
                if (!ok) return;
                try {
                  await ref.read(serviceRepositoryProvider).delete(widget.serviceId!);
                  ref.invalidate(servicesProvider);
                  if (context.mounted) context.pop();
                } catch (e) {
                  if (context.mounted) context.showError(e);
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // Imagen
            GestureDetector(
              onTap: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
                if (f != null) {
                  final bytes = await f.readAsBytes();
                  setState(() => _image = bytes);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 16 / 7,
                  child: _image != null
                      ? Image.memory(_image!, fit: BoxFit.cover)
                      : _imageUrl != null
                          ? CachedNetworkImage(imageUrl: _imageUrl!, fit: BoxFit.cover)
                          : ColoredBox(
                              color: t.colorScheme.surfaceContainerHighest,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Icon(Icons.add_photo_alternate_outlined, size: 36), Text('Agregar imagen')],
                              ),
                            ),
                ),
              ),
            ),
            const SectionTitle('Información'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => Validators.required(v, 'El nombre'),
            ),
            gap,
            DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            gap,
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duración (min) *'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 5 || n > 480) ? 'Entre 5 y 480' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _buffer,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Preparación (min)',
                      helperText: 'Tiempo entre turnos',
                    ),
                  ),
                ),
              ],
            ),

            const SectionTitle('Precios'),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Precio *', prefixText: r'$ '),
              validator: (v) => Validators.positiveNumber(v, 'El precio'),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _promo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio promocional', prefixText: r'$ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _promo.text.isEmpty
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _promoUntil ?? DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 730)),
                              helpText: 'Promo válida hasta',
                            );
                            setState(() => _promoUntil = d);
                          },
                    icon: const Icon(Icons.event),
                    label: Text(_promoUntil == null ? 'Sin vencimiento' : 'Hasta ${Fmt.date(_promoUntil!)}'),
                  ),
                ),
              ],
            ),
            if (_editing) _PriceHistory(serviceId: widget.serviceId!),

            const SectionTitle('Profesionales habilitados'),
            Text(
              _therapists.isEmpty ? 'Si no seleccionás ninguno, todos pueden realizarlo.' : '${_therapists.length} seleccionados',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in therapists)
                  FilterChip(
                    avatar: CircleAvatar(backgroundColor: p.color, radius: 6),
                    label: Text(p.fullName),
                    selected: _therapists.contains(p.id),
                    onSelected: (v) => setState(() => v ? _therapists.add(p.id) : _therapists.remove(p.id)),
                  ),
              ],
            ),

            const SectionTitle('Color en la agenda'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(int.parse(hex.replaceFirst('#', '0xFF'))),
                      child: _color == hex ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Servicio activo'),
              subtitle: const Text('Los inactivos no se pueden agendar'),
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar servicio')),
          ],
        ),
      ),
    );
  }
}

class _PriceHistory extends ConsumerWidget {
  const _PriceHistory({required this.serviceId});
  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(priceHistoryProvider(serviceId)).valueOrNull ?? const <PriceChange>[];
    if (history.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_rounded),
      title: Text('Historial de precios (${history.length})'),
      children: [
        for (final h in history)
          ListTile(
            dense: true,
            title: Text(h.oldPrice == null
                ? 'Precio inicial ${Fmt.money(h.newPrice)}'
                : '${Fmt.money(h.oldPrice)} → ${Fmt.money(h.newPrice)}'),
            subtitle: Text('${Fmt.date(h.changedAt)}${h.changedBy == null ? '' : ' · ${h.changedBy}'}'
                '${h.newPromo == null ? '' : ' · promo ${Fmt.money(h.newPromo)}'}'),
          ),
      ],
    );
  }
}
