import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../center/data/supabase_center_repository.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import 'report_definitions.dart';
import 'report_exporter.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  ReportType _type = ReportType.sales;
  ReportGroup _group = ReportGroup.day;
  late DateTimeRange _range;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().dateOnly;
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
  }

  ReportQuery get _query => ReportQuery(type: _type, from: _range.start, to: _range.end, group: _group);

  void _preset(ReportGroup g) {
    final now = DateTime.now().dateOnly;
    setState(() {
      _group = g;
      _range = switch (g) {
        ReportGroup.day => DateTimeRange(start: DateTime(now.year, now.month), end: now),
        ReportGroup.week => DateTimeRange(start: now.subtract(const Duration(days: 7 * 12)), end: now),
        ReportGroup.month => DateTimeRange(start: DateTime(now.year), end: now),
        ReportGroup.year => DateTimeRange(start: DateTime(now.year - 4), end: now),
      };
    });
  }

  Future<void> _export(bool pdf, List<Map<String, dynamic>> rows) async {
    setState(() => _exporting = true);
    try {
      final center = await ref.read(centerProvider.future);
      final exporter = ReportExporter(centerName: center.name, logoUrl: center.logoUrl);
      pdf ? await exporter.pdf(_query, rows) : await exporter.excel(_query, rows);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(reportProvider(_query));
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final r in ReportType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(r.icon, size: 18),
                      label: Text(r.label),
                      selected: _type == r,
                      onSelected: (_) => setState(() => _type = r),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text('${Fmt.date(_range.start)} – ${Fmt.date(_range.end)}'),
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _range,
                      );
                      if (r != null) setState(() => _range = r);
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_type.grouped)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<ReportGroup>(
                segments: [for (final g in ReportGroup.values) ButtonSegment(value: g, label: Text(g.label))],
                selected: {_group},
                onSelectionChanged: (s) => _preset(s.first),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncValueView(
              value: data,
              onRetry: () => ref.invalidate(reportProvider(_query)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(icon: Icons.insert_chart_outlined, title: 'Sin datos en el período');
                }
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                            columnSpacing: 20,
                            columns: [
                              for (final c in _type.columns)
                                DataColumn(
                                  label: Text(c.label),
                                  numeric: c.kind == ColumnKind.money || c.kind == ColumnKind.int,
                                ),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(cells: [for (final c in _type.columns) DataCell(Text(c.format(r[c.key])))]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _exporting ? null : () => _export(false, rows),
                                icon: const Icon(Icons.table_view_rounded),
                                label: const Text('Excel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _exporting ? null : () => _export(true, rows),
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                label: const Text('PDF'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
