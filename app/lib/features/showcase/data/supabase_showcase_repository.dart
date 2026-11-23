import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/showcase.dart';

class SupabaseShowcaseRepository implements ShowcaseRepository {
  SupabaseShowcaseRepository(this._db);
  final SupabaseClient _db;

  static const _bucket = 'showcase';
  static const _postSelect = '*, service:services(name), combo:combos(name), product:products(name)';
  static const _giftSelect = '*, product:products(name, gift_template_url)';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// Sube la imagen bajo {center_id}/… (las políticas de Storage validan la carpeta).
  Future<String> _upload(String folder, Uint8List bytes) async {
    final center = await _db.rpc<String>('current_center_id');
    final path = '$center/$folder/${const Uuid().v4()}.jpg';
    await _db.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000'),
        );
    return _db.storage.from(_bucket).getPublicUrl(path);
  }

  @override
  Future<List<Product>> products() => _guard(() async {
        final rows = await _db.from('products').select().order('sort_order').order('name');
        return rows.map(Product.fromJson).toList();
      });

  @override
  Future<Product> saveProduct(Product p, {Uint8List? image, Uint8List? templateImage}) => _guard(() async {
        var row = p.toRow();
        if (image != null) row = {...row, 'image_url': await _upload('products', image)};
        if (templateImage != null) {
          row = {...row, 'gift_template_url': await _upload('gift-templates', templateImage)};
        }
        final saved = p.id == null
            ? await _db.from('products').insert(row).select().single()
            : await _db.from('products').update(row).eq('id', p.id!).select().single();
        return Product.fromJson(saved);
      });

  @override
  Future<void> deleteProduct(String id) => _guard(() => _db.from('products').delete().eq('id', id));

  @override
  Future<List<GiftCard>> giftCards() => _guard(() async {
        final rows = await _db.from('gift_cards').select(_giftSelect).order('created_at', ascending: false);
        return rows.map(GiftCard.fromJson).toList();
      });

  @override
  Future<GiftCard> saveGiftCard(GiftCard g) => _guard(() async {
        final saved = await _db.from('gift_cards').insert(g.toRow()).select(_giftSelect).single();
        return GiftCard.fromJson(saved);
      });

  @override
  Future<void> setGiftCardStatus(String id, String status) => _guard(() => _db.from('gift_cards').update({
        'status': status,
        'redeemed_at': status == 'canjeada' ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', id));

  @override
  Future<List<PromoPost>> posts() => _guard(() async {
        final rows = await _db.from('promo_posts').select(_postSelect).order('starts_on', ascending: false);
        return rows.map(PromoPost.fromJson).toList();
      });

  @override
  Future<PromoPost> savePost(PromoPost p, {Uint8List? image}) => _guard(() async {
        var row = p.toRow();
        if (image != null) row = {...row, 'image_url': await _upload('posts', image)};
        final saved = p.id == null
            ? await _db.from('promo_posts').insert(row).select(_postSelect).single()
            : await _db.from('promo_posts').update(row).eq('id', p.id!).select(_postSelect).single();
        return PromoPost.fromJson(saved);
      });

  @override
  Future<void> deletePost(String id) => _guard(() => _db.from('promo_posts').delete().eq('id', id));

  @override
  Future<void> publishToTelegram(String postId) =>
      _guard(() => _db.functions.invoke('telegram-broadcast', body: {'post_id': postId}));

  @override
  Future<Map<String, dynamic>> publicCatalog() => _guard(() async {
        final json = await _db.rpc<Map<String, dynamic>>('public_catalog');
        return json;
      });
}

final showcaseRepositoryProvider = Provider<ShowcaseRepository>(
  (ref) => SupabaseShowcaseRepository(ref.watch(supabaseClientProvider)),
);

final productsProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(showcaseRepositoryProvider).products(),
);

final giftCardsProvider = FutureProvider.autoDispose<List<GiftCard>>(
  (ref) => ref.watch(showcaseRepositoryProvider).giftCards(),
);

final postsProvider = FutureProvider.autoDispose<List<PromoPost>>(
  (ref) => ref.watch(showcaseRepositoryProvider).posts(),
);

final publicCatalogProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(showcaseRepositoryProvider).publicCatalog(),
);
