import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../agenda/presentation/agenda_providers.dart';
import '../../agenda/presentation/widgets/appointment_tile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../center/data/supabase_center_repository.dart';
import '../../center/presentation/center_logo.dart';
import '../domain/dashboard_summary.dart';
import 'dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionUserProvider);
    final summary = ref.watch(dashboardProvider);
    final period = ref.watch(dashboardPeriodProvider);
    final t = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Buen día' : (hour < 20 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.invalidate(todayAppointmentsProvider);
          await ref.read(dashboardProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text('$greeting, ${user.fullName.split(' ').first}'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CenterLogo(url: ref.watch(centerProvider).valueOrNull?.logoUrl, size: 36, radius: 10),
                ),
                IconButton(
                  tooltip: 'Notificaciones',
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () => context.push('/mas/notificaciones'),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.longDate(DateTime.now()),
                        style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<DashboardPeriod>(
                        segments: [
                          for (final p in DashboardPeriod.values) ButtonSegment(value: p, label: Text(p.label)),
                        ],
                        selected: {period},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => ref.read(dashboardPeriodProvider.notifier).state = s.first,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(
                child: AsyncValueView(
                  value: summary,
                  onRetry: () => ref.invalidate(dashboardProvider),
                  loading: const SizedBox(height: 400, child: LoadingList(items: 4, height: 96)),
                  data: (s) => _DashboardBody(summary: s, showRevenue: user.canViewRevenue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.summary, required this.showRevenue});
  final DashboardSummary summary;
  final bool showRevenue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100 ? 4 : (width >= 600 ? 3 : 2);

    final kpis = <Widget>[
      _KpiCard(icon: Icons.event_available_rounded, label: 'Turnos de hoy', value: '${s.todayAppointments}', color: AppColors.confirmed),
      if (showRevenue) ...[
        _KpiCard(icon: Icons.payments_rounded, label: 'Facturación hoy', value: Fmt.money(s.revenueToday), color: AppColors.completed),
        _KpiCard(icon: Icons.trending_up_rounded, label: 'Facturación período', value: Fmt.compactMoney(s.revenuePeriod), color: AppColors.sage),
      ],
      _KpiCard(icon: Icons.person_add_alt_rounded, label: 'Clientes nuevos', value: '${s.newClients}', color: AppColors.terracotta),
      _KpiCard(icon: Icons.groups_rounded, label: 'Clientes activos (90 d)', value: '${s.activeClients}', color: AppColors.sageLight),
      _KpiCard(
        icon: Icons.event_busy_rounded,
        label: 'Tasa de cancelación',
        value: '${s.cancellationRate.toStringAsFixed(1)} %',
        color: AppColors.cancelled,
        hint: 'Ausentismo ${s.noShowRate.toStringAsFixed(1)} %',
      ),
      if (showRevenue && s.pendingPayments > 0)
        _KpiCard(icon: Icons.receipt_long_rounded, label: 'Pagos pendientes', value: '${s.pendingPayments}', color: AppColors.pending),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: kpis,
        ),
        const SectionTitle('Próximos turnos de hoy'),
        const _TodayAppointments(),
        if (showRevenue && s.revenueByDay.isNotEmpty) ...[
          const SectionTitle('Facturación diaria'),
          _ChartCard(height: 220, child: _RevenueChart(points: s.revenueByDay)),
        ],
        if (s.topServices.isNotEmpty) ...[
          const SectionTitle('Servicios más vendidos'),
          _ChartCard(child: _ServiceRanking(items: s.topServices, showRevenue: showRevenue)),
        ],
        if (s.bottomServices.isNotEmpty) ...[
          const SectionTitle('Servicios menos vendidos'),
          _ChartCard(child: _ServiceRanking(items: s.bottomServices, showRevenue: false, muted: true)),
        ],
        if (s.peakHours.isNotEmpty) ...[
          const SectionTitle('Horarios con mayor demanda'),
          _ChartCard(height: 200, child: _PeakHoursChart(data: s.peakHours)),
        ],
        if (showRevenue && s.revenueByMethod.isNotEmpty) ...[
          const SectionTitle('Cobros por medio de pago'),
          _ChartCard(child: _MethodBreakdown(data: s.revenueByMethod)),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.icon, required this.label, required this.value, required this.color, this.hint});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                if (hint != null)
                  Text(hint!, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child, this.height});
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
          child: height == null ? child : SizedBox(height: height, child: child),
        ),
      );
}

class _TodayAppointments extends ConsumerWidget {
  const _TodayAppointments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView(
      value: ref.watch(todayAppointmentsProvider),
      onRetry: () => ref.invalidate(todayAppointmentsProvider),
      loading: const SizedBox(height: 160, child: LoadingList(items: 2)),
      data: (list) {
        final now = DateTime.now();
        final upcoming = list.where((a) => a.status.isActive && a.endsAt.isAfter(now)).take(4).toList();
        if (upcoming.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(children: [Icon(Icons.self_improvement), SizedBox(width: 12), Text('No hay más turnos por hoy')]),
            ),
          );
        }
        return Column(
          children: [
            for (final a in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppointmentTile(appointment: a),
              ),
          ],
        );
      },
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points});
  final List<(DateTime, num)> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = points.map((p) => p.$2).fold<num>(0, math.max).toDouble();
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2.toDouble())];
    final labelEvery = math.max(1, (points.length / 6).ceil());

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(Fmt.compactMoney(v), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= points.length || i % labelEvery != 0) return const SizedBox.shrink();
                final d = points[i].$1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.day}/${d.month}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${Fmt.date(points[s.x.toInt()].$1)}\n${Fmt.money(s.y)}',
                  TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3,
            dotData: FlDotData(show: points.length < 15),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary.withValues(alpha: 0.28), scheme.primary.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 400),
    );
  }
}

class _ServiceRanking extends StatelessWidget {
  const _ServiceRanking({required this.items, required this.showRevenue, this.muted = false});
  final List<NamedCount> items;
  final bool showRevenue;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final maxCount = items.map((e) => e.count).fold<int>(1, math.max);
    final color = muted ? AppColors.noShow : t.colorScheme.primary;

    return Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.name, style: t.textTheme.bodyMedium)),
                    Text('${e.count} ${e.count == 1 ? 'sesión' : 'sesiones'}',
                        style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (showRevenue) ...[
                      const SizedBox(width: 10),
                      Text(Fmt.compactMoney(e.revenue),
                          style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: e.count / maxCount),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PeakHoursChart extends StatelessWidget {
  const _PeakHoursChart({required this.data});
  final Map<int, int> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hours = [for (var h = 8; h <= 21; h++) h];
    final maxV = data.values.fold<int>(1, math.max);

    return BarChart(
      BarChartData(
        maxY: maxV * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${v.toInt()}h', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${group.x}:00 · ${rod.toY.toInt()} turnos',
              TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (final h in hours)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(
                toY: (data[h] ?? 0).toDouble(),
                width: 14,
                borderRadius: BorderRadius.circular(5),
                color: (data[h] ?? 0) == maxV ? AppColors.terracotta : scheme.primary.withValues(alpha: 0.75),
              ),
            ]),
        ],
      ),
    );
  }
}

class _MethodBreakdown extends StatelessWidget {
  const _MethodBreakdown({required this.data});
  final Map<String, num> data;

  static const _labels = {
    'cash': ('Efectivo', Icons.payments_outlined),
    'transfer': ('Transferencia', Icons.account_balance_outlined),
    'card': ('Tarjeta', Icons.credit_card),
    'mercado_pago': ('Mercado Pago', Icons.qr_code_2),
  };

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<num>(0, (a, b) => a + b);
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        for (final e in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(_labels[e.key]?.$2 ?? Icons.attach_money),
            title: Text(_labels[e.key]?.$1 ?? e.key),
            subtitle: Text('${total == 0 ? 0 : (e.value * 100 / total).toStringAsFixed(0)} % del total'),
            trailing: Text(Fmt.money(e.value), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
