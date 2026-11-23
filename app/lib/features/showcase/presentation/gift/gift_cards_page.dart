import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/supabase_showcase_repository.dart';
import '../../domain/showcase.dart';

/// Tarjetas emitidas: consulta y cambio de estado (canjeada / anulada).
class GiftCardsPage extends ConsumerWidget {
  const GiftCardsPage({super.key});

  static const _labels = {
    'activa': 'Activa',
    'canjeada': 'Canjeada',
    'vencida': 'Vencida',
    'anulada': 'Anulada',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(giftCardsProvider);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tarjetas de regalo')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(giftCardsProvider.future),
        child: AsyncValueView(
          value: cards,
          onRetry: () => ref.invalidate(giftCardsProvider),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.card_giftcard_rounded,
                    title: 'Sin tarjetas emitidas',
                    message: 'Las tarjetas que emitas desde un producto de tipo tarjeta de regalo aparecen acá.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final g = list[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.card_giftcard_rounded),
                        title: Text(g.recipientName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${g.code} · ${g.productName ?? ''}\n'
                          'Válida ${Fmt.date(g.validFrom)} – ${Fmt.date(g.validUntil)} · ${Fmt.money(g.amount)}',
                          style: t.textTheme.bodySmall,
                        ),
                        isThreeLine: true,
                        trailing: g.status == 'activa'
                            ? PopupMenuButton<String>(
                                onSelected: (s) async {
                                  try {
                                    await ref.read(showcaseRepositoryProvider).setGiftCardStatus(g.id!, s);
                                    ref.invalidate(giftCardsProvider);
                                  } catch (e) {
                                    if (context.mounted) context.showError(e);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'canjeada', child: Text('Marcar canjeada')),
                                  PopupMenuItem(value: 'anulada', child: Text('Anular')),
                                ],
                              )
                            : Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(_labels[g.status] ?? g.status),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
