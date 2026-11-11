import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../services/domain/service.dart';
import '../../services/presentation/services_providers.dart';
import '../data/supabase_showcase_repository.dart';
import '../domain/showcase.dart';

enum _LinkKind { none, service, combo, product }

/// Alta/edición de una publicación promocional de la vitrina.
class PostFormPage extends ConsumerStatefulWidget {
  const PostFormPage({super.key, this.post});
  final PromoPost? post;

  @override
  ConsumerState<PostFormPage> createState() => _PostFormPageState();
}

class _PostFormPageState extends ConsumerState<PostFormPage> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.post?.title);
  late final _body = TextEditingController(text: widget.post?.body);
  late final _cta = TextEditingController(text: widget.post?.ctaLabel ?? 'Reservar por WhatsApp');
  late DateTime _starts = widget.post?.startsOn ?? DateTime.now().dateOnly;
  late DateTime? _ends = widget.post?.endsOn;
  late bool _active = widget.post?.isActive ?? true;
  late bool _featured = widget.post?.isFeatured ?? false;
  late _LinkKind _kind = widget.post?.serviceId != null
      ? _LinkKind.service
      : widget.post?.comboId != null
          ? _LinkKind.combo
          : widget.post?.productId != null
              ? _LinkKind.product
              : _LinkKind.none;
  late String? _linkedId = widget.post?.serviceId ?? widget.post?.comboId ?? widget.post?.productId;
  Uint8List? _image;
  bool _saving = false;

  bool get _editing => widget.post?.id != null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _cta.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(showcaseRepositoryProvider).savePost(
            PromoPost(
              id: widget.post?.id,
              title: _title.text,
              body: _body.text.trim().isEmpty ? null : _body.text,
              imageUrl: widget.post?.imageUrl,
              serviceId: _kind == _LinkKind.service ? _linkedId : null,
              comboId: _kind == _LinkKind.combo ? _linkedId : null,
              productId: _kind == _LinkKind.product ? _linkedId : null,
              ctaLabel: _cta.text.trim().isEmpty ? 'Reservar por WhatsApp' : _cta.text,
              startsOn: _starts,
              endsOn: _ends,
              isActive: _active,
              isFeatured: _featured,
            ),
            image: _image,
          );
      ref.invalidate(postsProvider);
      if (mounted) {
        context.showSnack(_editing ? 'Promoción actualizada' : 'Promoción creada');
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
    final t = Theme.of(context);
    const gap = SizedBox(height: 12);
    final services = ref.watch(servicesProvider).valueOrNull ?? const <Service>[];
    final combos = ref.watch(combosProvider).valueOrNull ?? const <Combo>[];
    final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];

    final options = switch (_kind) {
      _LinkKind.service => [for (final s in services) DropdownMenuItem<String>(value: s.id!, child: Text(s.name))],
      _LinkKind.combo => [for (final c in combos) DropdownMenuItem<String>(value: c.id, child: Text(c.name))],
      _LinkKind.product => [for (final p in products) DropdownMenuItem<String>(value: p.id!, child: Text(p.name))],
      _LinkKind.none => <DropdownMenuItem<String>>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar promoción' : 'Nueva promoción'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await context.confirm('Eliminar promoción', '¿Eliminar "${widget.post!.title}"?',
                    ok: 'Eliminar', destructive: true)) {
                  return;
                }
                try {
                  await ref.read(showcaseRepositoryProvider).deletePost(widget.post!.id!);
                  ref.invalidate(postsProvider);
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
            GestureDetector(
              onTap: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
                if (f != null) {
                  final bytes = await f.readAsBytes();
                  setState(() => _image = bytes);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _image != null
                      ? Image.memory(_image!, fit: BoxFit.cover)
                      : widget.post?.imageUrl != null
                          ? CachedNetworkImage(imageUrl: widget.post!.imageUrl!, fit: BoxFit.cover)
                          : ColoredBox(
                              color: t.colorScheme.surfaceContainerHighest,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined, size: 36),
                                  Text('Imagen de la promoción (16:9)'),
                                ],
                              ),
                            ),
                ),
              ),
            ),
            const SectionTitle('Contenido'),
            TextFormField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Título *', hintText: 'Ej: 2x1 en Drenaje Linfático'),
              validator: (v) => Validators.required(v, 'El título'),
            ),
            TextFormField(
              controller: _body,
              maxLines: 4,
              maxLength: 600,
              decoration: const InputDecoration(labelText: 'Texto', hintText: 'Detalle, condiciones, cupos…'),
            ),
            TextFormField(
              controller: _cta,
              decoration: const InputDecoration(labelText: 'Texto del botón', helperText: 'Abre WhatsApp con un mensaje prearmado'),
            ),

            const SectionTitle('Vincular a'),
            SegmentedButton<_LinkKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _LinkKind.none, label: Text('Nada')),
                ButtonSegment(value: _LinkKind.service, label: Text('Servicio')),
                ButtonSegment(value: _LinkKind.combo, label: Text('Combo')),
                ButtonSegment(value: _LinkKind.product, label: Text('Producto')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _linkedId = null;
              }),
            ),
            if (_kind != _LinkKind.none) ...[
              gap,
              DropdownButtonFormField<String>(
                value: options.any((o) => o.value == _linkedId) ? _linkedId : null,
                items: options,
                decoration: const InputDecoration(labelText: 'Elegir'),
                onChanged: (v) => setState(() => _linkedId = v),
              ),
            ],

            const SectionTitle('Vigencia'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('Desde ${Fmt.date(_starts)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _starts,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (d != null) setState(() => _starts = d);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_busy),
                    label: Text(_ends == null ? 'Sin fin' : 'Hasta ${Fmt.date(_ends!)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _ends ?? _starts.add(const Duration(days: 14)),
                        firstDate: _starts,
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      setState(() => _ends = d);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _featured,
              title: const Text('Destacada'),
              subtitle: const Text('Se muestra como banner principal del catálogo'),
              onChanged: (v) => setState(() => _featured = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Activa'),
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar promoción')),
          ],
        ),
      ),
    );
  }
}
