import 'package:flutter/foundation.dart';

@immutable
class Product {
  const Product({
    this.id,
    required this.name,
    required this.price,
    this.description,
    this.category,
    this.brand,
    this.promoPrice,
    this.stock,
    this.imageUrl,
    this.isActive = true,
    this.isFeatured = false,
    this.sortOrder = 0,
    this.code,
  });

  final String? id;
  final String name;

  /// Código propio del producto (carga masiva por Excel, migración 11). Solo se muestra:
  /// no va en [toRow], así editar el producto desde la app no lo borra.
  final String? code;
  final String? description;
  final String? category;
  final String? brand;
  final num price;
  final num? promoPrice;
  final int? stock; // null = no se controla stock
  final String? imageUrl;
  final bool isActive;
  final bool isFeatured;
  final int sortOrder;

  num get effectivePrice => promoPrice ?? price;
  bool get inStock => stock == null || stock! > 0;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        category: j['category'] as String?,
        brand: j['brand'] as String?,
        price: j['price'] as num,
        promoPrice: j['promo_price'] as num?,
        stock: (j['stock'] as num?)?.toInt(),
        imageUrl: j['image_url'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        isFeatured: j['is_featured'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        code: j['code'] as String?,
      );

  Map<String, dynamic> toRow() => {
        'name': name.trim(),
        'description': description?.trim(),
        'category': category?.trim(),
        'brand': brand?.trim(),
        'price': price,
        'promo_price': promoPrice,
        'stock': stock,
        'image_url': imageUrl,
        'is_active': isActive,
        'is_featured': isFeatured,
        'sort_order': sortOrder,
      };
}

/// Publicación promocional de la vitrina (banner): puede vincularse a un servicio, combo o producto.
@immutable
class PromoPost {
  const PromoPost({
    this.id,
    required this.title,
    this.body,
    this.imageUrl,
    this.serviceId,
    this.comboId,
    this.productId,
    this.linkedName,
    this.ctaLabel = 'Reservar por WhatsApp',
    required this.startsOn,
    this.endsOn,
    this.isActive = true,
    this.isFeatured = false,
    this.publishedTelegramAt,
  });

  final String? id;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? serviceId;
  final String? comboId;
  final String? productId;
  final String? linkedName;
  final String ctaLabel;
  final DateTime startsOn;
  final DateTime? endsOn;
  final bool isActive;
  final bool isFeatured;
  final DateTime? publishedTelegramAt;

  bool get isLive {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return isActive && !startsOn.isAfter(d) && (endsOn == null || !endsOn!.isBefore(d));
  }

  factory PromoPost.fromJson(Map<String, dynamic> j) {
    String? nameOf(String k) => (j[k] as Map<String, dynamic>?)?['name'] as String?;
    return PromoPost(
      id: j['id'] as String?,
      title: j['title'] as String,
      body: j['body'] as String?,
      imageUrl: j['image_url'] as String?,
      serviceId: j['service_id'] as String?,
      comboId: j['combo_id'] as String?,
      productId: j['product_id'] as String?,
      linkedName: nameOf('service') ?? nameOf('combo') ?? nameOf('product'),
      ctaLabel: j['cta_label'] as String? ?? 'Reservar por WhatsApp',
      startsOn: DateTime.parse(j['starts_on'] as String),
      endsOn: DateTime.tryParse(j['ends_on'] as String? ?? ''),
      isActive: j['is_active'] as bool? ?? true,
      isFeatured: j['is_featured'] as bool? ?? false,
      publishedTelegramAt: DateTime.tryParse(j['published_telegram_at'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'body': body?.trim(),
        'image_url': imageUrl,
        'service_id': serviceId,
        'combo_id': comboId,
        'product_id': productId,
        'cta_label': ctaLabel.trim(),
        'starts_on': startsOn.toIso8601String().substring(0, 10),
        'ends_on': endsOn?.toIso8601String().substring(0, 10),
        'is_active': isActive,
        'is_featured': isFeatured,
      };
}

abstract interface class ShowcaseRepository {
  Future<List<Product>> products();
  Future<Product> saveProduct(Product p, {Uint8List? image});
  Future<void> deleteProduct(String id);

  Future<List<PromoPost>> posts();
  Future<PromoPost> savePost(PromoPost p, {Uint8List? image});
  Future<void> deletePost(String id);

  /// Publica la promoción en el canal de Telegram del centro.
  Future<void> publishToTelegram(String postId);

  /// Catálogo público (sin sesión).
  Future<Map<String, dynamic>> publicCatalog();
}
