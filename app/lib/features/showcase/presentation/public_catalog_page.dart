import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../center/presentation/center_logo.dart';
import '../data/supabase_showcase_repository.dart';

/// Catálogo público: servicios, combos, productos y promociones vigentes.
/// Accesible sin iniciar sesión en la versión web (/catalogo) para compartir con clientes.
class PublicCatalogPage extends ConsumerWidget {
  const PublicCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(publicCatalogProvider);
    return Scaffold(
      body: AsyncValueView<Map<String, dynamic>>(
        value: catalog,
        onRetry: () => ref.invalidate(publicCatalogProvider),
        loading: const Center(child: CircularProgressIndicator()),
        data: (data) {
          if (data['enabled'] != true) {
            return const EmptyState(icon: Icons.storefront_outlined, title: 'Catálogo no disponible');
          }
          return _CatalogBody(data: data);
        },
      ),
    );
  }
}

typedef _Json = Map<String, dynamic>;

class _CatalogBody extends StatelessWidget {
  const _CatalogBody({required this.data});
  final _Json data;

  _Json get center => data['center'] as _Json;
  List<_Json> _list(String k) => ((data[k] as List<dynamic>?) ?? const []).cast<_Json>();

  Future<void> _whatsApp(String text) async {
    final phone = (center['whatsapp'] as String?)?.replaceAll(RegExp(r'\D'), '');
    if (phone == null || phone.isEmpty) return;
    final normalized = phone.startsWith('54') ? phone : '549$phone';
    await launchUrl(
      Uri.parse('https://wa.me/$normalized?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final posts = _list('posts');
    final services = _list('services');
    final combos = _list('combos');
    final products = _list('products');
    final hasWhatsApp = (center['whatsapp'] as String?)?.isNotEmpty ?? false;

    final byCategory = <String, List<_Json>>{};
    for (final s in services) {
      byCategory.putIfAbsent((s['category'] as String?) ?? 'Servicios', () => []).add(s);
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          automaticallyImplyLeading: Navigator.of(context).canPop(),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.sage.withValues(alpha: 0.30), t.colorScheme.surface],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CenterLogo(url: center['logo_url'] as String?, size: 84),
                        const SizedBox(height: 12),
                        Text(center['name'] as String? ?? '', style: t.textTheme.headlineMedium, textAlign: TextAlign.center),
                        if (center['description'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(center['description'] as String,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ContactBar(center: center, onWhatsApp: () => _whatsApp('¡Hola! Quiero reservar un turno.')),
                    if (posts.isNotEmpty) ...[
                      const SectionTitle('PROMOCIONES'),
                      _PromoCarousel(
                        posts: posts,
                        onTap: hasWhatsApp ? (p) => _whatsApp('¡Hola! Vi la promo "${p['title']}" y quiero reservar.') : null,
                      ),
                    ],
                    for (final entry in byCategory.entries) ...[
                      SectionTitle(entry.key.toUpperCase()),
                      for (final s in entry.value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ServiceRow(
                            service: s,
                            onBook: hasWhatsApp ? () => _whatsApp('¡Hola! Quiero reservar ${s['name']}.') : null,
                          ),
                        ),
                    ],
                    if (combos.isNotEmpty) ...[
                      const SectionTitle('COMBOS'),
                      for (final c in combos)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: const Icon(Icons.card_giftcard_rounded, color: AppColors.terracotta),
                            title: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(((c['services'] as List<dynamic>?) ?? const []).join(' + ')),
                            trailing: Text(Fmt.money(c['price'] as num),
                                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            onTap: hasWhatsApp ? () => _whatsApp('¡Hola! Me interesa el ${c['name']}.') : null,
                          ),
                        ),
                    ],
                    if (products.isNotEmpty) ...[
                      const SectionTitle('PRODUCTOS'),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.7,
                        ),
                        itemCount: products.length,
                        itemBuilder: (_, i) => _ProductTile(
                          product: products[i],
                          onAsk: hasWhatsApp ? () => _whatsApp('¡Hola! Quiero consultar por ${products[i]['name']}.') : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactBar extends StatelessWidget {
  const _ContactBar({required this.center, required this.onWhatsApp});
  final _Json center;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final ig = center['instagram'] as String?;
    final address = center['address'] as String?;
    final phone = center['phone'] as String?;
    final web = center['website'] as String?;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if ((center['whatsapp'] as String?)?.isNotEmpty ?? false)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onWhatsApp,
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Reservar por WhatsApp'),
          ),
        if (ig != null && ig.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => launchUrl(Uri.parse('https://instagram.com/$ig'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text('@$ig'),
          ),
        if (phone != null && phone.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            icon: const Icon(Icons.phone_outlined),
            label: Text(phone),
          ),
        if (address != null && address.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.place_outlined),
            label: Text(address),
          ),
        if (web != null && web.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => launchUrl(Uri.parse(web.startsWith('http') ? web : 'https://$web'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.language),
            label: const Text('Sitio web'),
          ),
      ],
    );
  }
}

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel({required this.posts, this.onTap});
  final List<_Json> posts;
  final void Function(_Json post)? onTap;

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.posts.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final p = widget.posts[i];
              final image = p['image_url'] as String?;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onTap == null ? null : () => widget.onTap!(p),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)
                        else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [AppColors.sage, AppColors.terracotta]),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.35, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['title'] as String,
                                  style: t.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                              if (p['body'] != null)
                                Text(p['body'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (widget.onTap != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: AppColors.terracotta, borderRadius: BorderRadius.circular(20)),
                                      child: Text(p['cta_label'] as String? ?? 'Reservar',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                  const Spacer(),
                                  if (p['ends_on'] != null)
                                    Text('Hasta ${Fmt.date(DateTime.parse(p['ends_on'] as String))}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.posts.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.posts.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? t.colorScheme.primary : t.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, this.onBook});
  final _Json service;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final promo = service['promo_price'] as num?;
    final price = service['price'] as num;
    final image = service['image_url'] as String?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          if (image != null)
            SizedBox(width: 88, height: 96, child: CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service['name'] as String, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (service['description'] != null)
                    Text(service['description'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: t.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(Fmt.duration((service['duration_minutes'] as num).toInt()), style: t.textTheme.labelSmall),
                      const Spacer(),
                      if (promo != null) ...[
                        Text(Fmt.money(price), style: t.textTheme.labelSmall?.copyWith(decoration: TextDecoration.lineThrough)),
                        const SizedBox(width: 6),
                      ],
                      Text(Fmt.money(promo ?? price),
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: promo != null ? t.colorScheme.secondary : null,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onBook != null)
            IconButton(tooltip: 'Reservar', icon: const Icon(Icons.chat_rounded), onPressed: onBook),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, this.onAsk});
  final _Json product;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final promo = product['promo_price'] as num?;
    final price = product['price'] as num;
    final image = product['image_url'] as String?;
    final inStock = product['in_stock'] as bool? ?? true;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAsk,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: image != null
                  ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppColors.sageLight.withValues(alpha: 0.35),
                      child: const Icon(Icons.shopping_bag_outlined, size: 40, color: AppColors.sage),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'] as String,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (promo != null) ...[
                        Text(Fmt.money(price), style: t.textTheme.labelSmall?.copyWith(decoration: TextDecoration.lineThrough)),
                        const SizedBox(width: 6),
                      ],
                      Text(Fmt.money(promo ?? price), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  if (!inStock) Text('Sin stock', style: t.textTheme.labelSmall?.copyWith(color: AppColors.cancelled)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
