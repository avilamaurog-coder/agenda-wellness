import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../payments/domain/payment.dart';
import '../domain/entities/client.dart';
import '../domain/repositories/client_repository.dart';
import 'client_mapper.dart';

class SupabaseClientRepository implements ClientRepository {
  SupabaseClientRepository(this._db, {required this.centerId});

  final SupabaseClient _db;
  final String centerId;
  static const _bucket = 'clinical-photos';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<List<Client>> search({String query = '', int page = 0, int pageSize = 30}) => _guard(() async {
        var q = _db.from('clients').select().isFilter('deleted_at', null);
        // Se eliminan caracteres reservados de la sintaxis `or` de PostgREST.
        final term = query.trim().replaceAll(RegExp(r'[,()*%]'), ' ').trim();
        if (term.isNotEmpty) {
          final parts = term.split(RegExp(r'\s+'));
          for (final p in parts) {
            q = q.or('first_name.ilike.%$p%,last_name.ilike.%$p%,dni.ilike.%$p%,phone.ilike.%$p%,email.ilike.%$p%');
          }
        }
        final from = page * pageSize;
        final rows = await q.order('last_name').order('first_name').range(from, from + pageSize - 1);
        return rows.map(ClientMapper.fromRow).toList();
      });

  @override
  Future<Client> getById(String id) => _guard(() async {
        final row = await _db.from('clients').select().eq('id', id).single();
        return ClientMapper.fromRow(row);
      });

  @override
  Future<ClientStats> stats(String id) => _guard(() async {
        final row = await _db.from('client_stats').select().eq('client_id', id).maybeSingle();
        return ClientMapper.statsFromRow(row);
      });

  @override
  Future<Client> create(Client client) => _guard(() async {
        final row = await _db.from('clients').insert(ClientMapper.toRow(client)).select().single();
        return ClientMapper.fromRow(row);
      });

  @override
  Future<Client> update(Client client) => _guard(() async {
        final row = await _db.from('clients').update(ClientMapper.toRow(client)).eq('id', client.id!).select().single();
        return ClientMapper.fromRow(row);
      });

  @override
  Future<void> archive(String id) => _guard(() async {
        await _db.from('clients').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
      });

  @override
  Future<List<ClinicalRecord>> clinicalRecords(String clientId) => _guard(() async {
        final rows = await _db
            .from('clinical_records')
            .select('*, therapist:profiles(full_name), clinical_photos(storage_path)')
            .eq('client_id', clientId)
            .order('record_date', ascending: false);
        return rows.map(ClientMapper.recordFromRow).toList();
      });

  @override
  Future<ClinicalRecord> addClinicalRecord(ClinicalRecord r, {List<Uint8List> photos = const []}) =>
      _guard(() async {
        final row = await _db
            .from('clinical_records')
            .insert({
              'client_id': r.clientId,
              'appointment_id': r.appointmentId,
              'therapist_id': _db.auth.currentUser!.id,
              'record_date': r.recordDate.toIso8601String().substring(0, 10),
              'evaluation': r.evaluation,
              'observations': r.observations,
              'treatment_goals': r.treatmentGoals,
              'evolution': r.evolution,
              'pain_scale': r.painScale,
            })
            .select('id')
            .single();
        final recordId = row['id'] as String;

        // Ruta: {center}/{client}/{uuid}.jpg  → las políticas de Storage validan ambos segmentos.
        for (final bytes in photos) {
          final path = '$centerId/${r.clientId}/${const Uuid().v4()}.jpg';
          await _db.storage.from(_bucket).uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
              );
          await _db.from('clinical_photos').insert({'record_id': recordId, 'storage_path': path});
        }

        final full = await _db
            .from('clinical_records')
            .select('*, therapist:profiles(full_name), clinical_photos(storage_path)')
            .eq('id', recordId)
            .single();
        return ClientMapper.recordFromRow(full);
      });

  @override
  Future<String> signedPhotoUrl(String storagePath) =>
      _guard(() => _db.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10));

  @override
  Future<List<Payment>> payments(String clientId) => _guard(() async {
        final rows = await _db.from('payments').select().eq('client_id', clientId).order('paid_at', ascending: false);
        return rows.map(Payment.fromJson).toList();
      });

  @override
  Future<String> regenerateTelegramCode(String clientId) =>
      _guard(() async => await _db.rpc<String>('regenerate_telegram_code', params: {'p_client_id': clientId}));

  @override
  Future<void> unlinkTelegram(String clientId) =>
      _guard(() => _db.rpc<void>('unlink_telegram', params: {'p_client_id': clientId}));
}
