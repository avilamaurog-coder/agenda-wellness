import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/supabase_showcase_repository.dart';
import '../../domain/showcase.dart';
import 'gift_card_preview.dart';

/// Emite una tarjeta de regalo: carga destinatario y vigencia, la guarda y la comparte como JPG.
class GiftCardFormPage extends ConsumerStatefulWidget {
  const GiftCardFormPage({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<GiftCardFormPage> createState() => _GiftCardFormPageState();
}

class _GiftCardFormPageState extends ConsumerState<GiftCardFormPage> {
  final _form = GlobalKey<FormState>();
  final _captureKey = GlobalKey();
  final _name = TextEditingController();
  late DateTime _from = DateTime.now().dateOnly;
  late DateTime _until = _from.add(const Duration(days: 90));
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _from : _until,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_until.isBefore(_from)) _until = _from;
      } else {
        _until = picked;
      }
    });
  }

  Future<void> _emitAndShare() async {
    if (!_form.currentState!.validate()) return;
    if (widget.product.giftTemplateUrl == null) {
      context.showSnack('Primero cargá la plantilla en el producto', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(showcaseRepositoryProvider).saveGiftCard(
            GiftCard(
              productId: widget.product.id,
              recipientName: _name.text,
              amount: widget.product.effectivePrice,
              validFrom: _from,
              validUntil: _until,
            ),
          );
      ref.invalidate(giftCardsProvider);
      final jpg = await captureGiftCardJpg(_captureKey);
      if (mounted) context.showSnack('Tarjeta guardada · código ${saved.code}');
      await Share.shareXFiles(
        [XFile.fromData(jpg, name: 'tarjeta-${saved.code}.jpg', mimeType: 'image/jpeg')],
        text: 'Tu tarjeta de regalo',
      );
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: const Text('Emitir tarjeta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: GiftCardPreview(
                templateUrl: p.giftTemplateUrl,
                recipientName: _name.text,
                validFrom: _from,
                validUntil: _until,
              ),
            ),
            const SizedBox(height: 8),
            Text('${p.name} · ${Fmt.money(p.effectivePrice)}',
                style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SectionTitle('Destinatario'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del destinatario *'),
              validator: (v) => Validators.required(v, 'El nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SectionTitle('Vigencia'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('Válido desde ${Fmt.date(_from)}'),
                    onPressed: () => _pick(start: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_busy),
                    label: Text('Hasta ${Fmt.date(_until)}'),
                    onPressed: () => _pick(start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.share_rounded),
              onPressed: _saving ? null : _emitAndShare,
              label: Text(_saving ? 'Guardando…' : 'Guardar y compartir JPG'),
            ),
          ],
        ),
      ),
    );
  }
}
