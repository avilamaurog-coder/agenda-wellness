import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_appointment_repository.dart';
import '../domain/entities/appointment.dart';
import '../domain/repositories/appointment_repository.dart';
import '../domain/usecases/appointment_usecases.dart';

final appointmentRepositoryProvider = Provider<AppointmentRepository>(
  (ref) => SupabaseAppointmentRepository(ref.watch(supabaseClientProvider)),
);

final createAppointmentProvider = Provider((ref) => CreateAppointment(ref.watch(appointmentRepositoryProvider)));
final rescheduleAppointmentProvider =
    Provider((ref) => RescheduleAppointment(ref.watch(appointmentRepositoryProvider)));
final cancelAppointmentProvider = Provider((ref) => CancelAppointment(ref.watch(appointmentRepositoryProvider)));

enum AgendaView { day, week, month }

/// Estado de la vista de agenda: fecha seleccionada, modo y filtro de profesional.
class AgendaFilter {
  const AgendaFilter({required this.date, this.view = AgendaView.day, this.therapistId});
  final DateTime date;
  final AgendaView view;
  final String? therapistId;

  (DateTime, DateTime) get range => switch (view) {
        AgendaView.day => (date.dateOnly, date.dateOnly.add(const Duration(days: 1))),
        AgendaView.week => (date.startOfWeek, date.startOfWeek.add(const Duration(days: 7))),
        AgendaView.month => (
            DateTime(date.year, date.month).startOfWeek,
            DateTime(date.year, date.month + 1).startOfWeek.add(const Duration(days: 7)),
          ),
      };

  AgendaFilter copyWith({DateTime? date, AgendaView? view, String? therapistId, bool clearTherapist = false}) =>
      AgendaFilter(
        date: date ?? this.date,
        view: view ?? this.view,
        therapistId: clearTherapist ? null : (therapistId ?? this.therapistId),
      );
}

class AgendaFilterNotifier extends Notifier<AgendaFilter> {
  @override
  AgendaFilter build() {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Un profesional ve por defecto solo su agenda
    return AgendaFilter(date: DateTime.now(), therapistId: user?.isTherapist == true ? user!.id : null);
  }

  void setDate(DateTime d) => state = state.copyWith(date: d);
  void setView(AgendaView v) => state = state.copyWith(view: v);
  void setTherapist(String? id) => state = state.copyWith(therapistId: id, clearTherapist: id == null);
  void today() => state = state.copyWith(date: DateTime.now());

  void shift(int direction) {
    final d = state.date;
    state = state.copyWith(
      date: switch (state.view) {
        AgendaView.day => d.add(Duration(days: direction)),
        AgendaView.week => d.add(Duration(days: 7 * direction)),
        AgendaView.month => DateTime(d.year, d.month + direction, 1),
      },
    );
  }
}

final agendaFilterProvider = NotifierProvider<AgendaFilterNotifier, AgendaFilter>(AgendaFilterNotifier.new);

/// Turnos del rango visible. Se refresca solo ante cambios en tiempo real.
class AgendaController extends AsyncNotifier<List<Appointment>> {
  AppointmentRepository get _repo => ref.read(appointmentRepositoryProvider);

  @override
  Future<List<Appointment>> build() async {
    final f = ref.watch(agendaFilterProvider);
    final sub = _repo.changes().listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
    final (from, to) = f.range;
    return _repo.range(from, to, therapistId: f.therapistId);
  }

  /// Drag & drop con actualización optimista y rollback ante error.
  Future<void> move(Appointment appt, DateTime newStart, {String? therapistId, String? reason}) async {
    final previous = state.valueOrNull ?? [];
    state = AsyncData([
      for (final a in previous) a.id == appt.id ? a.movedTo(newStart, therapistId: therapistId) : a,
    ]);
    try {
      final updated =
          await ref.read(rescheduleAppointmentProvider)(appt, newStart, therapistId: therapistId, reason: reason);
      state = AsyncData([for (final a in state.valueOrNull ?? previous) a.id == updated.id ? updated : a]);
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  void replace(Appointment updated) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncData([for (final a in list) a.id == updated.id ? updated : a]);
  }
}

final agendaProvider = AsyncNotifierProvider<AgendaController, List<Appointment>>(AgendaController.new);

final appointmentProvider = FutureProvider.autoDispose.family<Appointment, String>(
  (ref, id) => ref.watch(appointmentRepositoryProvider).getById(id),
);

final clientAppointmentsProvider = FutureProvider.autoDispose.family<List<Appointment>, String>(
  (ref, clientId) => ref.watch(appointmentRepositoryProvider).byClient(clientId),
);

typedef SlotQuery = ({DateTime date, String serviceId, String? therapistId});

final availableSlotsProvider = FutureProvider.autoDispose.family<List<TimeSlot>, SlotQuery>(
  (ref, q) => ref.watch(appointmentRepositoryProvider).availableSlots(q.date, q.serviceId, therapistId: q.therapistId),
);

/// Turnos de hoy para el dashboard (independiente del filtro de la agenda).
final todayAppointmentsProvider = FutureProvider.autoDispose<List<Appointment>>((ref) {
  final user = ref.watch(sessionUserProvider);
  final today = DateTime.now().dateOnly;
  return ref
      .watch(appointmentRepositoryProvider)
      .range(today, today.add(const Duration(days: 1)), therapistId: user.isTherapist ? user.id : null);
});
