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
    this.isGiftCard = false,
    this.giftTemplateUrl,
  });

  final String? id;
  final String name;
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
  final bool isGiftCard;
  final String? giftTemplateUrl; // plantilla de la tarjeta (sin nombre ni fechas)

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
        isGiftCard: j['is_gift_card'] as bool? ?? false,
        giftTemplateUrl: j['gift_template_url'] as String?,
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
        'is_gift_card': isGiftCard,
        'gift_template_url': giftTemplateUrl,
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

/// Tarjeta de regalo emitida a un destinatario (el diseño vive en el producto).
@immutable
class GiftCard {
  const GiftCard({
    this.id,
    this.productId,
    this.productName,
    this.templateUrl,
    this.code = '',
    required this.recipientName,
    required this.amount,
    required this.validFrom,
    required this.validUntil,
    this.status = 'activa',
  });

  final String? id;
  final String? productId;
  final String? productName;
  final String? templateUrl;
  final String code; // lo asigna la base de datos
  final String recipientName;
  final num amount; // monto al momento de emitir
  final DateTime validFrom;
  final DateTime validUntil;
  final String status; // activa | canjeada | vencida | anulada

  factory GiftCard.fromJson(Map<String, dynamic> j) {
    final product = j['product'] as Map<String, dynamic>?;
    return GiftCard(
      id: j['id'] as String?,
      productId: j['product_id'] as String?,
      productName: product?['name'] as String?,
      templateUrl: product?['gift_template_url'] as String?,
      code: j['code'] as String? ?? '',
      recipientName: j['recipient_name'] as String,
      amount: j['amount'] as num,
      validFrom: DateTime.parse(j['valid_from'] as String),
      validUntil: DateTime.parse(j['valid_until'] as String),
      status: j['status'] as String? ?? 'activa',
    );
  }

  Map<String, dynamic> toRow() => {
        'product_id': productId,
        'recipient_name': recipientName.trim(),
        'amount': amount,
        'valid_from': validFrom.toIso8601String().substring(0, 10),
        'valid_until': validUntil.toIso8601String().substring(0, 10),
        'status': status,
      };
}

abstract interface class ShowcaseRepository {
  Future<List<Product>> products();
  Future<Product> saveProduct(Product p, {Uint8List? image, Uint8List? templateImage});
  Future<void> deleteProduct(String id);

  Future<List<GiftCard>> giftCards();
  Future<GiftCard> saveGiftCard(GiftCard g);
  Future<void> setGiftCardStatus(String id, String status);

  Future<List<PromoPost>> posts();
  Future<PromoPost> savePost(PromoPost p, {Uint8List? image});
  Future<void> deletePost(String id);

  /// Publica la promoción en el canal de Telegram del centro.
  Future<void> publishToTelegram(String postId);

  /// Catálogo público (sin sesión).
  Future<Map<String, dynamic>> publicCatalog();
}
