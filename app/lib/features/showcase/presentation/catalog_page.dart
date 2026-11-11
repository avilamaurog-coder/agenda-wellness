import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../services/presentation/pages/services_page.dart';
import '../data/supabase_showcase_repository.dart';
import '../domain/showcase.dart';

/// Catálogo: servicios, productos y publicaciones promocionales (vitrina).
class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo'),
          actions: [
            IconButton(
              tooltip: 'Ver catálogo público',
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => context.push('/catalogo'),
            ),
            if (Env.catalogUrl.isNotEmpty)
              IconButton(
                tooltip: 'Compartir catálogo',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => Share.share('Conocé nuestros servicios y promociones 🌿 ${Env.catalogUrl}'),
              ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Servicios'), Tab(text: 'Productos'), Tab(text: 'Promociones')]),
        ),
        body: const TabBarView(children: [ServicesPage(embedded: true), _ProductsTab(), _PostsTab()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- Productos
class _ProductsTab extends ConsumerWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final products = ref.watch(productsProvider);

    return Scaffold(
      floatingActionButton: user.isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'fab-product',
              onPressed: () => context.push('/servicios/productos/nuevo'),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Producto'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(productsProvider.future),
        child: AsyncValueView(
          value: products,
          onRetry: () => ref.invalidate(productsProvider),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Sin productos',
                    message: 'Cargá aceites, cremas, gift cards o kits para publicitarlos.',
                  ),
                ])
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ProductCard(
                    product: list[i],
                    onTap: user.isAdmin ? () => context.push('/servicios/productos/${list[i].id}', extra: list[i]) : null,
                  ),
                ),
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.onTap, this.footer});
  final Product product;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final t = Theme.of(context);
    return Opacity(
      opacity: p.isActive ? 1 : 0.5,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    p.imageUrl != null
                        ? CachedNetworkImage(imageUrl: p.imageUrl!, fit: BoxFit.cover)
                        : ColoredBox(
                            color: AppColors.sageLight.withValues(alpha: 0.35),
                            child: const Icon(Icons.shopping_bag_outlined, size: 40, color: AppColors.sage),
                          ),
                    if (p.isFeatured)
                      const Positioned(top: 8, left: 8, child: _Badge('Destacado', AppColors.terracotta)),
                    if (!p.inStock)
                      const Positioned(top: 8, right: 8, child: _Badge('Sin stock', AppColors.noShow)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (p.category != null)
                      Text(p.category!, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (p.promoPrice != null) ...[
                          Text(Fmt.money(p.price),
                              style: t.textTheme.labelSmall?.copyWith(decoration: TextDecoration.lineThrough)),
                          const SizedBox(width: 6),
                        ],
                        Text(Fmt.money(p.effectivePrice),
                            style: t.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: p.promoPrice != null ? t.colorScheme.secondary : null,
                            )),
                      ],
                    ),
                    if (footer != null) ...[const SizedBox(height: 8), footer!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

// ---------------------------------------------------------------------------- Promociones
class _PostsTab extends ConsumerWidget {
  const _PostsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final posts = ref.watch(postsProvider);

    return Scaffold(
      floatingActionButton: user.isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'fab-post',
              onPressed: () => context.push('/servicios/promociones/nueva'),
              icon: const Icon(Icons.campaign_rounded),
              label: const Text('Promoción'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(postsProvider.future),
        child: AsyncValueView(
          value: posts,
          onRetry: () => ref.invalidate(postsProvider),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Sin promociones',
                    message: 'Creá publicaciones para el catálogo público, WhatsApp, Instagram y Telegram.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _PostCard(post: list[i], canEdit: user.isAdmin),
                ),
        ),
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post, required this.canEdit});
  final PromoPost post;
  final bool canEdit;

  String _shareText() {
    final until = post.endsOn == null ? '' : '\n⏳ Hasta el ${Fmt.date(post.endsOn!)}';
    final link = Env.catalogUrl.isEmpty ? '' : '\n\n👉 ${Env.catalogUrl}';
    return '✨ ${post.title}\n\n${post.body ?? ''}$until$link';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = post;
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canEdit ? () => context.push('/servicios/promociones/${p.id}', extra: p) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.imageUrl != null)
              AspectRatio(aspectRatio: 16 / 9, child: CachedNetworkImage(imageUrl: p.imageUrl!, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(p.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(p.isLive ? 'Activa' : (p.isActive ? 'Programada / vencida' : 'Pausada')),
                        backgroundColor: (p.isLive ? AppColors.completed : AppColors.noShow).withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                  if (p.body != null) Text(p.body!, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (p.linkedName != null) '🔗 ${p.linkedName}',
                      'Desde ${Fmt.date(p.startsOn)}${p.endsOn == null ? '' : ' hasta ${Fmt.date(p.endsOn!)}'}',
                      if (p.publishedTelegramAt != null) 'Telegram ✓',
                    ].join(' · '),
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Compartir'),
                        onPressed: () => Share.share(_shareText(), subject: p.title),
                      ),
                      if (canEdit)
                        ActionChip(
                          avatar: const Icon(Icons.send_rounded, size: 18),
                          label: Text(p.publishedTelegramAt == null ? 'Publicar en Telegram' : 'Volver a publicar'),
                          onPressed: () async {
                            try {
                              await ref.read(showcaseRepositoryProvider).publishToTelegram(p.id!);
                              ref.invalidate(postsProvider);
                              if (context.mounted) context.showSnack('Publicado en el canal de Telegram');
                            } catch (e) {
                              if (context.mounted) context.showError(e);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
