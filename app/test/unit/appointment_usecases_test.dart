import 'package:agenda_wellness/core/errors/failure.dart';
import 'package:agenda_wellness/features/agenda/domain/entities/appointment.dart';
import 'package:agenda_wellness/features/agenda/domain/repositories/appointment_repository.dart';
import 'package:agenda_wellness/features/agenda/domain/usecases/appointment_usecases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements AppointmentRepository {}

Appointment _appt({AppointmentStatus status = AppointmentStatus.pending, int reschedules = 0, DateTime? start}) {
  final s = start ?? DateTime.now().add(const Duration(days: 1));
  return Appointment(
    id: 'a1',
    clientId: 'c1',
    clientName: 'Ana Pérez',
    therapistId: 't1',
    therapistName: 'Laura',
    startsAt: s,
    endsAt: s.add(const Duration(minutes: 60)),
    status: status,
    serviceName: 'Masaje Relajante',
    rescheduleCount: reschedules,
  );
}

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
    registerFallbackValue(DateTime(2026));
  });

  group('RescheduleAppointment', () {
    test('rechaza turnos cancelados', () {
      final uc = RescheduleAppointment(repo);
      expect(
        () => uc(_appt(status: AppointmentStatus.cancelled), DateTime.now().add(const Duration(days: 2))),
        throwsA(isA<Failure>()),
      );
      verifyNever(() => repo.reschedule(any(), any()));
    });

    test('rechaza horarios en el pasado', () {
      final uc = RescheduleAppointment(repo);
      expect(() => uc(_appt(), DateTime.now().subtract(const Duration(hours: 1))), throwsA(isA<Failure>()));
    });

    test('exige motivo tras 3 reprogramaciones', () {
      final uc = RescheduleAppointment(repo);
      expect(
        () => uc(_appt(reschedules: 3), DateTime.now().add(const Duration(days: 3))),
        throwsA(isA<Failure>()),
      );
    });

    test('delega en el repositorio cuando es válido', () async {
      final target = DateTime.now().add(const Duration(days: 3));
      final moved = _appt(start: target);
      when(() => repo.reschedule('a1', target, therapistId: null, reason: null)).thenAnswer((_) async => moved);

      final result = await RescheduleAppointment(repo)(_appt(), target);
      expect(result.startsAt, target);
    });
  });

  group('CancelAppointment', () {
    test('exige motivo', () {
      expect(() => CancelAppointment(repo)(_appt(), ' '), throwsA(isA<Failure>()));
    });
  });

  group('AppointmentStatus', () {
    test('máquina de estados coincide con la base de datos', () {
      expect(AppointmentStatus.pending.nextStates, contains(AppointmentStatus.confirmed));
      expect(AppointmentStatus.completed.nextStates, isEmpty);
      expect(AppointmentStatus.cancelled.nextStates, isEmpty);
    });
  });

  group('Appointment.movedTo', () {
    test('conserva la duración y vuelve a pendiente si estaba confirmado', () {
      final a = _appt(status: AppointmentStatus.confirmed);
      final target = a.startsAt.add(const Duration(hours: 2));
      final m = a.movedTo(target);
      expect(m.duration, a.duration);
      expect(m.status, AppointmentStatus.pending);
      expect(m.rescheduleCount, 1);
    });
  });
}
