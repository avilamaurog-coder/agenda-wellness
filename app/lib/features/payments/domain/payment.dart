import 'package:flutter/material.dart';

enum PaymentMethod {
  cash('cash', 'Efectivo', Icons.payments_outlined),
  transfer('transfer', 'Transferencia', Icons.account_balance_outlined),
  card('card', 'Tarjeta', Icons.credit_card),
  mercadoPago('mercado_pago', 'Mercado Pago', Icons.qr_code_2);

  const PaymentMethod(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  static PaymentMethod parse(String? v) =>
      PaymentMethod.values.firstWhere((m) => m.value == v, orElse: () => PaymentMethod.cash);
}

@immutable
class Payment {
  const Payment({
    this.id,
    required this.clientId,
    required this.amount,
    required this.method,
    this.appointmentId,
    this.status = 'paid',
    this.reference,
    this.notes,
    this.paidAt,
  });

  final String? id;
  final String clientId;
  final String? appointmentId;
  final num amount;
  final PaymentMethod method;
  final String status;
  final String? reference;
  final String? notes;
  final DateTime? paidAt;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: j['id'] as String,
        clientId: j['client_id'] as String,
        appointmentId: j['appointment_id'] as String?,
        amount: j['amount'] as num,
        method: PaymentMethod.parse(j['method'] as String?),
        status: j['status'] as String? ?? 'paid',
        reference: j['reference'] as String?,
        notes: j['notes'] as String?,
        paidAt: DateTime.tryParse(j['paid_at'] as String? ?? ''),
      );

  Map<String, dynamic> toInsert() => {
        'client_id': clientId,
        'appointment_id': appointmentId,
        'amount': amount,
        'method': method.value,
        'reference': reference,
        'notes': notes,
      };
}

abstract interface class PaymentRepository {
  Future<Payment> register(Payment payment);
  Future<List<Payment>> byAppointment(String appointmentId);
}
