import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../domain/service.dart';
import '../services_providers.dart';

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key, this.embedded = false});

  /// Dentro de la pestaña "Catálogo" no muestra su propia AppBar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final services = ref.watch(servicesProvider);
    final categories = ref.watch(serviceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];
    final combos = ref.watch(combosProvider).valueOrNull ?? const <Combo>[];

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Servicios')),
      floatingActionButton: user.canManageServices
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/servicios/nuevo'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Servicio'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(servicesProvider);
          ref.invalidate(combosProvider);
          await ref.read(servicesProvider.future);
        },
        child: AsyncValueView(
          value: services,
          onRetry: () => ref.invalidate(servicesProvider),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.spa_outlined, title: 'Todavía no hay servicios cargados');
            }
            final groups = <String, List<Service>>{};
            for (final s in list) {
              groups.putIfAbsent(s.categoryName ?? 'Otros', () => []).add(s);
            }
            final order = [
              ...categories.map((c) => c.name).where(groups.containsKey),
              ...groups.keys.where((k) => !categories.any((c) => c.name == k)),
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                for (final cat in order) ...[
                  SectionTitle(cat.toUpperCase()),
                  for (final s in groups[cat]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ServiceCard(service: s, canEdit: user.canManageServices),
                    ),
                ],
                if (combos.isNotEmpty) ...[
                  const SectionTitle('COMBOS'),
                  for (final c in combos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ComboCard(combo: c),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service, required this.canEdit});
  final Service service;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = service;
    final t = Theme.of(context);

    return Opacity(
      opacity: s.isActive ? 1 : 0.55,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canEdit ? () => context.push('/servicios/${s.id}') : null,
          child: Row(
            children: [
              SizedBox(
                width: 84,
                height: 92,
                child: s.imageUrl != null
                    ? CachedNetworkImage(imageUrl: s.imageUrl!, fit: BoxFit.cover)
                    : ColoredBox(
                        color: s.color.withValues(alpha: 0.35),
                        child: Icon(Icons.spa_rounded, color: s.color, size: 32),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        s.description ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: t.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(Fmt.duration(s.durationMinutes), style: t.textTheme.labelSmall),
                          const Spacer(),
                          if (s.hasActivePromo) ...[
                            Text(Fmt.money(s.price),
                                style: t.textTheme.labelSmall?.copyWith(decoration: TextDecoration.lineThrough)),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            Fmt.money(s.effectivePrice),
                            style: t.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: s.hasActivePromo ? t.colorScheme.secondary : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (canEdit)
                Switch(
                  value: s.isActive,
                  onChanged: (v) async {
                    try {
                      await ref.read(serviceRepositoryProvider).setActive(s.id!, v);
                      ref.invalidate(servicesProvider);
                    } catch (e) {
                      if (context.mounted) context.showError(e);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComboCard extends StatelessWidget {
  const _ComboCard({required this.combo});
  final Combo combo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.card_giftcard_rounded, color: t.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(child: Text(combo.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(Fmt.money(combo.price), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in combo.services) Chip(label: Text(s.name), visualDensity: VisualDensity.compact)],
            ),
            const SizedBox(height: 6),
            Text(
              '${Fmt.duration(combo.totalMinutes)}'
              '${combo.savings > 0 ? ' · Ahorro ${Fmt.money(combo.savings)}' : ''}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
