import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../domain/entities/appointment.dart';
import '../domain/repositories/appointment_repository.dart';

class SupabaseAppointmentRepository implements AppointmentRepository {
  SupabaseAppointmentRepository(this._db);
  final SupabaseClient _db;

  static const _view = 'appointments_view';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  @override
  Future<List<Appointment>> range(DateTime from, DateTime to, {String? therapistId}) => _guard(() async {
        var q = _db.from(_view).select().gte('starts_at', _iso(from)).lt('starts_at', _iso(to));
        if (therapistId != null) q = q.eq('therapist_id', therapistId);
        final rows = await q.order('starts_at');
        return rows.map(Appointment.fromJson).toList();
      });

  @override
  Future<List<Appointment>> byClient(String clientId) => _guard(() async {
        final rows = await _db.from(_view).select().eq('client_id', clientId).order('starts_at', ascending: false);
        return rows.map(Appointment.fromJson).toList();
      });

  @override
  Future<Appointment> getById(String id) => _guard(() async {
        final row = await _db.from(_view).select().eq('id', id).single();
        return Appointment.fromJson(row);
      });

  @override
  Future<Appointment> create(NewAppointment d) => _guard(() async {
        final row = await _db
            .from('appointments')
            .insert({
              'client_id': d.clientId,
              'therapist_id': d.therapistId,
              'service_id': d.serviceId,
              'combo_id': d.comboId,
              'starts_at': _iso(d.startsAt),
              // ends_at se calcula en el trigger a partir de la duración del servicio
              'ends_at': d.durationMinutes == null ? null : _iso(d.startsAt.add(Duration(minutes: d.durationMinutes!))),
              'price': d.price ?? 0, // 0 → el trigger aplica el precio vigente
              'discount_amount': d.discountAmount,
              'notes': d.notes,
            })
            .select('id')
            .single();
        return getById(row['id'] as String);
      });

  @override
  Future<Appointment> reschedule(String id, DateTime newStart, {String? therapistId, String? reason}) =>
      _guard(() async {
        await _db.rpc<dynamic>('reschedule_appointment', params: {
          'p_id': id,
          'p_new_start': _iso(newStart),
          'p_new_therapist': therapistId,
          'p_reason': reason,
        });
        return getById(id);
      });

  @override
  Future<Appointment> cancel(String id, String reason) => _guard(() async {
        await _db.rpc<dynamic>('cancel_appointment', params: {'p_id': id, 'p_reason': reason});
        return getById(id);
      });

  @override
  Future<Appointment> setStatus(String id, AppointmentStatus status) => _guard(() async {
        await _db.rpc<dynamic>('set_appointment_status', params: {'p_id': id, 'p_status': status.value});
        return getById(id);
      });

  @override
  Future<void> updateNotes(String id, String? notes) =>
      _guard(() => _db.from('appointments').update({'notes': notes}).eq('id', id));

  @override
  Future<List<TimeSlot>> availableSlots(DateTime date, String serviceId, {String? therapistId}) =>
      _guard(() async {
        final rows = await _db.rpc<List<dynamic>>('available_slots', params: {
          'p_date': date.toIso8601String().substring(0, 10),
          'p_service_id': serviceId,
          'p_therapist_id': therapistId,
        });
        return rows.map((r) => TimeSlot.fromJson(r as Map<String, dynamic>)).toList();
      });

  @override
  Future<List<TimeSlot>> suggestReschedule(String appointmentId) => _guard(() async {
        final rows = await _db.rpc<List<dynamic>>('suggest_reschedule', params: {'p_appointment_id': appointmentId});
        return rows.map((r) => TimeSlot.fromJson(r as Map<String, dynamic>)).toList();
      });

  @override
  Stream<void> changes() {
    final controller = StreamController<void>.broadcast();
    final channel = _db
        .channel('appointments-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          callback: (_) => controller.add(null),
        )
        .subscribe();
    controller.onCancel = () async {
      await _db.removeChannel(channel);
      await controller.close();
    };
    return controller.stream;
  }
}
