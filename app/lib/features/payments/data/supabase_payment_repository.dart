import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/payment.dart';

class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<Payment> register(Payment payment) async {
    try {
      final row = await _db.from('payments').insert(payment.toInsert()).select().single();
      return Payment.fromJson(row);
    } catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<List<Payment>> byAppointment(String appointmentId) async {
    try {
      final rows = await _db.from('payments').select().eq('appointment_id', appointmentId).order('paid_at');
      return rows.map(Payment.fromJson).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => SupabasePaymentRepository(ref.watch(supabaseClientProvider)),
);
