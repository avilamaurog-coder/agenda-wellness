import 'package:flutter/foundation.dart';

@immutable
class NamedCount {
  const NamedCount(this.name, this.count, [this.revenue = 0]);
  final String name;
  final int count;
  final num revenue;
}

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.from,
    required this.to,
    required this.todayAppointments,
    required this.todayByStatus,
    required this.revenueToday,
    required this.revenuePeriod,
    required this.revenueByMethod,
    required this.revenueByDay,
    required this.newClients,
    required this.activeClients,
    required this.topServices,
    required this.bottomServices,
    required this.peakHours,
    required this.peakWeekdays,
    required this.cancellationRate,
    required this.noShowRate,
    required this.pendingPayments,
  });

  final DateTime from;
  final DateTime to;
  final int todayAppointments;
  final Map<String, int> todayByStatus;
  final num revenueToday;
  final num revenuePeriod;
  final Map<String, num> revenueByMethod;
  final List<(DateTime, num)> revenueByDay;
  final int newClients;
  final int activeClients;
  final List<NamedCount> topServices;
  final List<NamedCount> bottomServices;
  final Map<int, int> peakHours; // hora → turnos
  final Map<int, int> peakWeekdays; // 1=lunes … 7=domingo
  final double cancellationRate;
  final double noShowRate;
  final int pendingPayments;

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => (v as num?)?.toInt() ?? 0;
    List<dynamic> l(Object? v) => (v as List<dynamic>?) ?? const [];
    Map<String, dynamic> m(Object? v) => (v as Map<String, dynamic>?) ?? const {};

    return DashboardSummary(
      from: DateTime.parse(m(j['period'])['from'] as String),
      to: DateTime.parse(m(j['period'])['to'] as String),
      todayAppointments: i(j['today_appointments']),
      todayByStatus: m(j['today_by_status']).map((k, v) => MapEntry(k, i(v))),
      revenueToday: j['revenue_today'] as num? ?? 0,
      revenuePeriod: j['revenue_period'] as num? ?? 0,
      revenueByMethod: m(j['revenue_by_method']).map((k, v) => MapEntry(k, v as num)),
      revenueByDay: l(j['revenue_by_day'])
          .map((e) => e as Map<String, dynamic>)
          .map((e) => (DateTime.parse(e['date'] as String), e['total'] as num))
          .toList(),
      newClients: i(j['new_clients']),
      activeClients: i(j['active_clients']),
      topServices: l(j['top_services'])
          .map((e) => e as Map<String, dynamic>)
          .map((e) => NamedCount(e['name'] as String, i(e['count']), e['revenue'] as num? ?? 0))
          .toList(),
      bottomServices: l(j['bottom_services'])
          .map((e) => e as Map<String, dynamic>)
          .map((e) => NamedCount(e['name'] as String, i(e['count'])))
          .toList(),
      peakHours: {
        for (final e in l(j['peak_hours']).cast<Map<String, dynamic>>()) i(e['hour']): i(e['count']),
      },
      peakWeekdays: {
        for (final e in l(j['peak_weekdays']).cast<Map<String, dynamic>>()) i(e['weekday']): i(e['count']),
      },
      cancellationRate: (j['cancellation_rate'] as num?)?.toDouble() ?? 0,
      noShowRate: (j['no_show_rate'] as num?)?.toDouble() ?? 0,
      pendingPayments: i(j['pending_payments']),
    );
  }
}

abstract interface class DashboardRepository {
  Future<DashboardSummary> summary({DateTime? from, DateTime? to});
}
