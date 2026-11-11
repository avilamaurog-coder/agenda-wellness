import 'dart:typed_data';

import 'package:flutter/material.dart';

@immutable
class ServiceCategory {
  const ServiceCategory({required this.id, required this.name, this.icon, this.sortOrder = 0});
  final String id;
  final String name;
  final String? icon;
  final int sortOrder;

  factory ServiceCategory.fromJson(Map<String, dynamic> j) => ServiceCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class Service {
  const Service({
    this.id,
    required this.name,
    required this.durationMinutes,
    required this.price,
    this.categoryId,
    this.categoryName,
    this.description,
    this.bufferMinutes = 0,
    this.promoPrice,
    this.promoValidUntil,
    this.imageUrl,
    this.colorHex,
    this.isActive = true,
    this.therapistIds = const [],
  });

  final String? id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? description;
  final int durationMinutes;
  final int bufferMinutes;
  final num price;
  final num? promoPrice;
  final DateTime? promoValidUntil;
  final String? imageUrl;
  final String? colorHex;
  final bool isActive;
  final List<String> therapistIds;

  bool get hasActivePromo =>
      promoPrice != null &&
      (promoValidUntil == null || !promoValidUntil!.isBefore(DateTime.now().copyWith(hour: 0, minute: 0)));

  num get effectivePrice => hasActivePromo ? promoPrice! : price;

  Color get color => colorHex == null ? const Color(0xFF8FA998) : Color(int.parse(colorHex!.replaceFirst('#', '0xFF')));

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'] as String,
        name: j['name'] as String,
        categoryId: j['category_id'] as String?,
        categoryName: (j['category'] as Map<String, dynamic>?)?['name'] as String?,
        description: j['description'] as String?,
        durationMinutes: (j['duration_minutes'] as num).toInt(),
        bufferMinutes: (j['buffer_minutes'] as num?)?.toInt() ?? 0,
        price: j['price'] as num,
        promoPrice: j['promo_price'] as num?,
        promoValidUntil: DateTime.tryParse(j['promo_valid_until'] as String? ?? ''),
        imageUrl: j['image_url'] as String?,
        colorHex: j['color_hex'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        therapistIds: ((j['service_therapists'] as List<dynamic>?) ?? const [])
            .map((e) => (e as Map<String, dynamic>)['therapist_id'] as String)
            .toList(),
      );

  Map<String, dynamic> toRow() => {
        'name': name.trim(),
        'category_id': categoryId,
        'description': description?.trim(),
        'duration_minutes': durationMinutes,
        'buffer_minutes': bufferMinutes,
        'price': price,
        'promo_price': promoPrice,
        'promo_valid_until': promoValidUntil?.toIso8601String().substring(0, 10),
        'image_url': imageUrl,
        'color_hex': colorHex,
        'is_active': isActive,
      };

  Service copyWith({bool? isActive, String? imageUrl}) => Service(
        id: id,
        name: name,
        categoryId: categoryId,
        categoryName: categoryName,
        description: description,
        durationMinutes: durationMinutes,
        bufferMinutes: bufferMinutes,
        price: price,
        promoPrice: promoPrice,
        promoValidUntil: promoValidUntil,
        imageUrl: imageUrl ?? this.imageUrl,
        colorHex: colorHex,
        isActive: isActive ?? this.isActive,
        therapistIds: therapistIds,
      );
}

@immutable
class Combo {
  const Combo({required this.id, required this.name, required this.price, this.description, this.services = const [], this.isActive = true});
  final String id;
  final String name;
  final String? description;
  final num price;
  final bool isActive;
  final List<Service> services;

  int get totalMinutes => services.fold(0, (s, e) => s + e.durationMinutes);
  num get regularPrice => services.fold<num>(0, (s, e) => s + e.price);
  num get savings => (regularPrice - price).clamp(0, double.infinity);

  factory Combo.fromJson(Map<String, dynamic> j) => Combo(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        price: j['price'] as num,
        isActive: j['is_active'] as bool? ?? true,
        services: ((j['combo_items'] as List<dynamic>?) ?? const [])
            .map((e) => Service.fromJson((e as Map<String, dynamic>)['service'] as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class PriceChange {
  const PriceChange({required this.changedAt, required this.newPrice, this.oldPrice, this.newPromo, this.changedBy});
  final DateTime changedAt;
  final num? oldPrice;
  final num newPrice;
  final num? newPromo;
  final String? changedBy;

  factory PriceChange.fromJson(Map<String, dynamic> j) => PriceChange(
        changedAt: DateTime.parse(j['changed_at'] as String).toLocal(),
        oldPrice: j['old_price'] as num?,
        newPrice: j['new_price'] as num,
        newPromo: j['new_promo_price'] as num?,
        changedBy: (j['profile'] as Map<String, dynamic>?)?['full_name'] as String?,
      );
}

abstract interface class ServiceRepository {
  Future<List<ServiceCategory>> categories();
  Future<List<Service>> services({bool onlyActive = false});
  Future<Service> save(Service service, {Uint8List? image});
  Future<void> setActive(String id, bool active);
  Future<void> delete(String id);
  Future<List<Combo>> combos();
  Future<List<PriceChange>> priceHistory(String serviceId);
}
