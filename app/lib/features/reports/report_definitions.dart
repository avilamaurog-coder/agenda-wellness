import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failure.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/utils/formatters.dart';

enum ReportGroup {
  day('day', 'Día'),
  week('week', 'Semana'),
  month('month', 'Mes'),
  year('year', 'Año');

  const ReportGroup(this.value, this.label);
  final String value;
  final String label;
}

enum ColumnKind { text, date, int, money, percent }

class ReportColumn {
  const ReportColumn(this.key, this.label, [this.kind = ColumnKind.text]);
  final String key;
  final String label;
  final ColumnKind kind;

  String format(Object? v) {
    if (v == null) return '—';
    return switch (kind) {
      ColumnKind.money => Fmt.money(v as num),
      ColumnKind.int => '${(v as num).toInt()}',
      ColumnKind.percent => '${(v as num).toStringAsFixed(1)} %',
      ColumnKind.date => Fmt.date(DateTime.parse(v as String)),
      ColumnKind.text => '$v',
    };
  }
}

/// Catálogo de reportes: cada uno mapea a una función RPC de PostgreSQL.
enum ReportType {
  sales('Ventas', Icons.point_of_sale_rounded, 'report_sales', true, [
    ReportColumn('period', 'Período', ColumnKind.date),
    ReportColumn('payments_count', 'Cobros', ColumnKind.int),
    ReportColumn('cash', 'Efectivo', ColumnKind.money),
    ReportColumn('transfer', 'Transferencia', ColumnKind.money),
    ReportColumn('card', 'Tarjeta', ColumnKind.money),
    ReportColumn('mercado_pago', 'Mercado Pago', ColumnKind.money),
    ReportColumn('total', 'Total', ColumnKind.money),
  ]),
  appointments('Turnos', Icons.event_note_rounded, 'report_appointments', true, [
    ReportColumn('period', 'Período', ColumnKind.date),
    ReportColumn('total', 'Total', ColumnKind.int),
    ReportColumn('completed', 'Completados', ColumnKind.int),
    ReportColumn('pending', 'Pendientes', ColumnKind.int),
    ReportColumn('cancelled', 'Cancelados', ColumnKind.int),
    ReportColumn('no_show', 'Ausentes', ColumnKind.int),
    ReportColumn('rescheduled', 'Reprogramados', ColumnKind.int),
  ]),
  services('Servicios', Icons.spa_rounded, 'report_services', false, [
    ReportColumn('service_name', 'Servicio'),
    ReportColumn('category', 'Categoría'),
    ReportColumn('sessions', 'Sesiones', ColumnKind.int),
    ReportColumn('revenue', 'Facturado', ColumnKind.money),
    ReportColumn('avg_ticket', 'Ticket prom.', ColumnKind.money),
  ]),
  clients('Clientes', Icons.people_rounded, 'report_clients', false, [
    ReportColumn('client_name', 'Cliente'),
    ReportColumn('visits', 'Visitas', ColumnKind.int),
    ReportColumn('cancellations', 'Cancelaciones', ColumnKind.int),
    ReportColumn('total_spent', 'Gastado', ColumnKind.money),
  ]),
  cancellations('Cancelaciones', Icons.event_busy_rounded, 'report_cancellations', false, [
    ReportColumn('event_date', 'Fecha', ColumnKind.date),
    ReportColumn('event', 'Tipo'),
    ReportColumn('client_name', 'Cliente'),
    ReportColumn('service_name', 'Servicio'),
    ReportColumn('reason', 'Motivo'),
    ReportColumn('performed_by', 'Registró'),
  ]);

  const ReportType(this.label, this.icon, this.rpc, this.grouped, this.columns);
  final String label;
  final IconData icon;
  final String rpc;
  final bool grouped;
  final List<ReportColumn> columns;
}

class ReportQuery {
  const ReportQuery({required this.type, required this.from, required this.to, this.group = ReportGroup.day});
  final ReportType type;
  final DateTime from;
  final DateTime to;
  final ReportGroup group;

  @override
  bool operator ==(Object o) =>
      o is ReportQuery && o.type == type && o.from == from && o.to == to && o.group == group;

  @override
  int get hashCode => Object.hash(type, from, to, group);
}

final reportProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, ReportQuery>((ref, q) async {
  final db = ref.watch(supabaseClientProvider);
  try {
    final rows = await db.rpc<List<dynamic>>(q.type.rpc, params: {
      'p_from': q.from.toIso8601String().substring(0, 10),
      'p_to': q.to.toIso8601String().substring(0, 10),
      if (q.type.grouped) 'p_group': q.group.value,
    });
    final list = rows.cast<Map<String, dynamic>>();
    if (q.type == ReportType.cancellations) {
      const labels = {'cancelled': 'Cancelación', 'rescheduled': 'Reprogramación', 'no_show': 'Ausencia'};
      return [for (final r in list) {...r, 'event': labels[r['event']] ?? r['event']}];
    }
    return list;
  } catch (e) {
    throw Failure.from(e);
  }
});
