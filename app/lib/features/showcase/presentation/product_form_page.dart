import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/supabase_showcase_repository.dart';
import '../domain/showcase.dart';

class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _description = TextEditingController(text: widget.product?.description);
  late final _category = TextEditingController(text: widget.product?.category);
  late final _brand = TextEditingController(text: widget.product?.brand);
  late final _price = TextEditingController(text: widget.product?.price.toStringAsFixed(0));
  late final _promo = TextEditingController(text: widget.product?.promoPrice?.toStringAsFixed(0));
  late final _stock = TextEditingController(text: widget.product?.stock?.toString());
  late bool _active = widget.product?.isActive ?? true;
  late bool _featured = widget.product?.isFeatured ?? false;
  Uint8List? _image;
  bool _saving = false;

  bool get _editing => widget.product?.id != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _category, _brand, _price, _promo, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final price = Validators.parseMoney(_price.text)!;
    final promo = Validators.parseMoney(_promo.text);
    if (promo != null && promo >= price) {
      context.showSnack('El precio promocional debe ser menor al precio', error: true);
      return;
    }
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(showcaseRepositoryProvider).saveProduct(
            Product(
              id: widget.product?.id,
              name: _name.text,
              description: v(_description),
              category: v(_category),
              brand: v(_brand),
              price: price,
              promoPrice: promo,
              stock: int.tryParse(_stock.text.trim()),
              imageUrl: widget.product?.imageUrl,
              isActive: _active,
              isFeatured: _featured,
              sortOrder: widget.product?.sortOrder ?? 0,
            ),
            image: _image,
          );
      ref.invalidate(productsProvider);
      if (mounted) {
        context.showSnack(_editing ? 'Producto actualizado' : 'Producto creado');
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
    const gap = SizedBox(height: 12);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar producto' : 'Nuevo producto'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await context.confirm('Eliminar producto', '¿Eliminar "${widget.product!.name}"?',
                    ok: 'Eliminar', destructive: true)) {
                  return;
                }
                try {
                  await ref.read(showcaseRepositoryProvider).deleteProduct(widget.product!.id!);
                  ref.invalidate(productsProvider);
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
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
                if (f != null) {
                  final bytes = await f.readAsBytes();
                  setState(() => _image = bytes);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: _image != null
                      ? Image.memory(_image!, fit: BoxFit.cover)
                      : widget.product?.imageUrl != null
                          ? CachedNetworkImage(imageUrl: widget.product!.imageUrl!, fit: BoxFit.cover)
                          : ColoredBox(
                              color: t.colorScheme.surfaceContainerHighest,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Icon(Icons.add_photo_alternate_outlined, size: 36), Text('Foto del producto')],
                              ),
                            ),
                ),
              ),
            ),
            const SectionTitle('Producto'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => Validators.required(v, 'El nombre'),
            ),
            gap,
            TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción')),
            gap,
            Row(
              children: [
                Expanded(child: TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Categoría'))),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'))),
              ],
            ),
            const SectionTitle('Precio y stock'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio *', prefixText: r'$ '),
                    validator: (v) => Validators.positiveNumber(v, 'El precio'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _promo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio promo', prefixText: r'$ '),
                  ),
                ),
              ],
            ),
            gap,
            TextFormField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock', helperText: 'Vacío = no controlar stock'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _featured,
              title: const Text('Destacado'),
              subtitle: const Text('Aparece primero en el catálogo público'),
              onChanged: (v) => setState(() => _featured = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Visible en el catálogo'),
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar producto')),
          ],
        ),
      ),
    );
  }
}
