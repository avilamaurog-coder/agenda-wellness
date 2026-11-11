import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/center.dart';

class SupabaseCenterRepository implements CenterRepository {
  SupabaseCenterRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<BusinessCenter> current() => _guard(() async {
        // RLS devuelve solo el centro del usuario
        final row = await _db.from('centers').select().limit(1).single();
        return BusinessCenter.fromJson(row);
      });

  @override
  Future<BusinessCenter> update(BusinessCenter c) => _guard(() async {
        final row = await _db.from('centers').update(c.toRow()).eq('id', c.id).select().single();
        return BusinessCenter.fromJson(row);
      });

  @override
  Future<String> uploadLogo(String centerId, Uint8List bytes, String extension) => _guard(() async {
        final ext = extension.toLowerCase().replaceAll('.', '');
        final mime = switch (ext) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          'svg' => 'image/svg+xml',
          _ => 'image/jpeg',
        };
        // Nombre único: evita que el logo viejo quede en caché de clientes y CDN
        final path = '$centerId/logo-${const Uuid().v4()}.$ext';
        await _db.storage.from('branding').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mime, cacheControl: '31536000'),
            );
        final url = _db.storage.from('branding').getPublicUrl(path);
        await _db.from('centers').update({'logo_url': url}).eq('id', centerId);
        return url;
      });

  @override
  Future<BusinessCenter?> publicBranding() async {
    try {
      final json = await _db.rpc<Map<String, dynamic>?>('public_branding');
      return json == null ? null : BusinessCenter.fromJson(json);
    } catch (_) {
      return null; // La marca es decorativa: nunca bloquea el login
    }
  }

  @override
  Future<List<BackupRecord>> backups() => _guard(() async {
        final rows = await _db.from('backups').select().order('started_at', ascending: false).limit(30);
        return rows.map(BackupRecord.fromJson).toList();
      });

  @override
  Future<void> runBackupNow() => _guard(() => _db.functions.invoke('backup', body: {'trigger': 'manual'}));
}

final centerRepositoryProvider = Provider<CenterRepository>(
  (ref) => SupabaseCenterRepository(ref.watch(supabaseClientProvider)),
);

/// Centro del usuario autenticado.
final centerProvider = FutureProvider<BusinessCenter>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(centerRepositoryProvider).current();
});

/// Marca pública, disponible antes de iniciar sesión.
final publicBrandingProvider = FutureProvider<BusinessCenter?>(
  (ref) => ref.watch(centerRepositoryProvider).publicBranding(),
);

final backupsProvider = FutureProvider.autoDispose<List<BackupRecord>>(
  (ref) => ref.watch(centerRepositoryProvider).backups(),
);
