import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../domain/service.dart';

class SupabaseServiceRepository implements ServiceRepository {
  SupabaseServiceRepository(this._db);
  final SupabaseClient _db;

  static const _select = '*, category:service_categories(name), service_therapists(therapist_id)';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<List<ServiceCategory>> categories() => _guard(() async {
        final rows = await _db.from('service_categories').select().order('sort_order');
        return rows.map(ServiceCategory.fromJson).toList();
      });

  @override
  Future<List<Service>> services({bool onlyActive = false}) => _guard(() async {
        var q = _db.from('services').select(_select).isFilter('deleted_at', null);
        if (onlyActive) q = q.eq('is_active', true);
        final rows = await q.order('name');
        return rows.map(Service.fromJson).toList();
      });

  @override
  Future<Service> save(Service s, {Uint8List? image}) => _guard(() async {
        var row = s.toRow();
        if (image != null) {
          final path = 'services/${const Uuid().v4()}.jpg';
          await _db.storage.from('service-images').uploadBinary(
                path,
                image,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          row = {...row, 'image_url': _db.storage.from('service-images').getPublicUrl(path)};
        }

        final saved = s.id == null
            ? await _db.from('services').insert(row).select('id').single()
            : await _db.from('services').update(row).eq('id', s.id!).select('id').single();
        final id = saved['id'] as String;

        // Sincroniza profesionales habilitados
        await _db.from('service_therapists').delete().eq('service_id', id);
        if (s.therapistIds.isNotEmpty) {
          await _db.from('service_therapists').insert(
                s.therapistIds.map((t) => {'service_id': id, 'therapist_id': t}).toList(),
              );
        }

        final full = await _db.from('services').select(_select).eq('id', id).single();
        return Service.fromJson(full);
      });

  @override
  Future<void> setActive(String id, bool active) =>
      _guard(() => _db.from('services').update({'is_active': active}).eq('id', id));

  @override
  Future<void> delete(String id) => _guard(() => _db
      .from('services')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'is_active': false}).eq('id', id));

  @override
  Future<List<Combo>> combos() => _guard(() async {
        final rows = await _db
            .from('combos')
            .select('*, combo_items(sort_order, service:services(*))')
            .order('name');
        return rows.map(Combo.fromJson).toList();
      });

  @override
  Future<List<PriceChange>> priceHistory(String serviceId) => _guard(() async {
        final rows = await _db
            .from('service_price_history')
            .select('*, profile:profiles(full_name)')
            .eq('service_id', serviceId)
            .order('changed_at', ascending: false);
        return rows.map(PriceChange.fromJson).toList();
      });
}
