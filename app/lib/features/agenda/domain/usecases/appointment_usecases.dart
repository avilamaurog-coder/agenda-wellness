import '../../../../core/errors/failure.dart';
import '../entities/appointment.dart';
import '../repositories/appointment_repository.dart';

/// Casos de uso de la agenda: concentran las reglas de negocio que no dependen
/// de la UI ni del backend. Las reglas críticas (solapamiento, permisos)
/// además se garantizan en la base de datos.

class CreateAppointment {
  const CreateAppointment(this._repo);
  final AppointmentRepository _repo;

  Future<Appointment> call(NewAppointment data) async {
    if (data.startsAt.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      throw const Failure('No se pueden crear turnos en el pasado.');
    }
    if (data.discountAmount < 0) throw const Failure('El descuento no puede ser negativo.');
    final created = await _repo.create(data);
    if (data.confirmed) return _repo.setStatus(created.id, AppointmentStatus.confirmed);
    return created;
  }
}

class RescheduleAppointment {
  const RescheduleAppointment(this._repo);
  final AppointmentRepository _repo;

  static const maxReschedules = 3;

  Future<Appointment> call(Appointment appt, DateTime newStart, {String? therapistId, String? reason}) {
    if (!appt.status.isActive) {
      throw Failure('Un turno ${appt.status.label.toLowerCase()} no se puede reprogramar.');
    }
    if (newStart.isBefore(DateTime.now())) {
      throw const Failure('Elegí un horario futuro.');
    }
    if (newStart == appt.startsAt && (therapistId == null || therapistId == appt.therapistId)) {
      return Future.value(appt);
    }
    if (appt.rescheduleCount >= maxReschedules && (reason == null || reason.trim().isEmpty)) {
      throw const Failure('Este turno ya fue reprogramado varias veces: indicá un motivo.');
    }
    return _repo.reschedule(appt.id, newStart, therapistId: therapistId, reason: reason);
  }
}

class CancelAppointment {
  const CancelAppointment(this._repo);
  final AppointmentRepository _repo;

  Future<Appointment> call(Appointment appt, String reason) {
    if (!appt.status.isActive) throw const Failure('El turno ya no está activo.');
    if (reason.trim().length < 3) throw const Failure('Indicá el motivo de la cancelación.');
    return _repo.cancel(appt.id, reason.trim());
  }
}
