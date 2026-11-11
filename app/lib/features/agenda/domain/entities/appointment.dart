import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

enum AppointmentStatus {
  pending('pending', 'Pendiente', AppColors.pending, Icons.schedule_rounded),
  confirmed('confirmed', 'Confirmado', AppColors.confirmed, Icons.check_circle_outline_rounded),
  completed('completed', 'Completado', AppColors.completed, Icons.task_alt_rounded),
  cancelled('cancelled', 'Cancelado', AppColors.cancelled, Icons.cancel_outlined),
  noShow('no_show', 'Ausente', AppColors.noShow, Icons.person_off_outlined);

  const AppointmentStatus(this.value, this.label, this.color, this.icon);
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  bool get isActive => this == pending || this == confirmed;

  /// Transiciones permitidas (espejo de `set_appointment_status` en SQL).
  List<AppointmentStatus> get nextStates => switch (this) {
        pending => [confirmed, completed, noShow],
        confirmed => [pending, completed, noShow],
        noShow => [completed],
        completed || cancelled => const [],
      };

  static AppointmentStatus parse(String? v) =>
      AppointmentStatus.values.firstWhere((s) => s.value == v, orElse: () => AppointmentStatus.pending);
}

@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.therapistId,
    required this.therapistName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.serviceName,
    this.clientPhone,
    this.therapistColor,
    this.serviceId,
    this.comboId,
    this.serviceColor,
    this.price = 0,
    this.discountAmount = 0,
    this.finalPrice = 0,
    this.paidAmount = 0,
    this.notes,
    this.cancellationReason,
    this.rescheduleCount = 0,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String? clientPhone;
  final String therapistId;
  final String therapistName;
  final String? therapistColor;
  final String? serviceId;
  final String? comboId;
  final String serviceName;
  final String? serviceColor;
  final DateTime startsAt;
  final DateTime endsAt;
  final AppointmentStatus status;
  final num price;
  final num discountAmount;
  final num finalPrice;
  final num paidAmount;
  final String? notes;
  final String? cancellationReason;
  final int rescheduleCount;

  Duration get duration => endsAt.difference(startsAt);
  num get balance => (finalPrice - paidAmount).clamp(0, double.infinity);
  bool get isPaid => paidAmount >= finalPrice && finalPrice > 0;
  bool get isPast => endsAt.isBefore(DateTime.now());

  Color get accent {
    final hex = serviceColor ?? therapistColor;
    if (hex == null) return status.color;
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  Appointment movedTo(DateTime newStart, {String? therapistId}) => Appointment(
        id: id,
        clientId: clientId,
        clientName: clientName,
        clientPhone: clientPhone,
        therapistId: therapistId ?? this.therapistId,
        therapistName: therapistName,
        therapistColor: therapistColor,
        serviceId: serviceId,
        comboId: comboId,
        serviceName: serviceName,
        serviceColor: serviceColor,
        startsAt: newStart,
        endsAt: newStart.add(duration),
        status: status == AppointmentStatus.confirmed ? AppointmentStatus.pending : status,
        price: price,
        discountAmount: discountAmount,
        finalPrice: finalPrice,
        paidAmount: paidAmount,
        notes: notes,
        cancellationReason: cancellationReason,
        rescheduleCount: rescheduleCount + 1,
      );

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] as String,
        clientId: j['client_id'] as String,
        clientName: j['client_name'] as String? ?? '',
        clientPhone: j['client_phone'] as String?,
        therapistId: j['therapist_id'] as String,
        therapistName: j['therapist_name'] as String? ?? '',
        therapistColor: j['therapist_color'] as String?,
        serviceId: j['service_id'] as String?,
        comboId: j['combo_id'] as String?,
        serviceName: j['service_name'] as String? ?? '',
        serviceColor: j['service_color'] as String?,
        startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(j['ends_at'] as String).toLocal(),
        status: AppointmentStatus.parse(j['status'] as String?),
        price: j['price'] as num? ?? 0,
        discountAmount: j['discount_amount'] as num? ?? 0,
        finalPrice: j['final_price'] as num? ?? 0,
        paidAmount: j['paid_amount'] as num? ?? 0,
        notes: j['notes'] as String?,
        cancellationReason: j['cancellation_reason'] as String?,
        rescheduleCount: (j['reschedule_count'] as num?)?.toInt() ?? 0,
      );
}

/// Datos para crear un turno.
@immutable
class NewAppointment {
  const NewAppointment({
    required this.clientId,
    required this.therapistId,
    required this.startsAt,
    this.serviceId,
    this.comboId,
    this.durationMinutes,
    this.price,
    this.discountAmount = 0,
    this.notes,
    this.confirmed = false,
  }) : assert(serviceId != null || comboId != null, 'Debe indicar servicio o combo');

  final String clientId;
  final String therapistId;
  final DateTime startsAt;
  final String? serviceId;
  final String? comboId;
  final int? durationMinutes;
  final num? price;
  final num discountAmount;
  final String? notes;
  final bool confirmed;
}

@immutable
class TimeSlot {
  const TimeSlot({required this.therapistId, required this.therapistName, required this.start, required this.end});
  final String therapistId;
  final String therapistName;
  final DateTime start;
  final DateTime end;

  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
        therapistId: j['therapist_id'] as String,
        therapistName: j['therapist_name'] as String,
        start: DateTime.parse(j['slot_start'] as String).toLocal(),
        end: DateTime.parse(j['slot_end'] as String).toLocal(),
      );
}
