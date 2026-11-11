import '../entities/appointment.dart';

abstract interface class AppointmentRepository {
  /// Turnos en el rango [from, to). Si [therapistId] es null trae todos los visibles por RLS.
  Future<List<Appointment>> range(DateTime from, DateTime to, {String? therapistId});

  Future<List<Appointment>> byClient(String clientId);
  Future<Appointment> getById(String id);

  Future<Appointment> create(NewAppointment data);
  Future<Appointment> reschedule(String id, DateTime newStart, {String? therapistId, String? reason});
  Future<Appointment> cancel(String id, String reason);
  Future<Appointment> setStatus(String id, AppointmentStatus status);
  Future<void> updateNotes(String id, String? notes);

  Future<List<TimeSlot>> availableSlots(DateTime date, String serviceId, {String? therapistId});
  Future<List<TimeSlot>> suggestReschedule(String appointmentId);

  /// Emite cada vez que cambia algún turno del centro (Supabase Realtime).
  Stream<void> changes();
}
