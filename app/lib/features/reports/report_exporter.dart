import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/formatters.dart';
import 'report_definitions.dart';

/// Exporta un reporte tabular a PDF (vista previa/compartir) o Excel (.xlsx).
class ReportExporter {
  const ReportExporter({required this.centerName, this.logoUrl});
  final String centerName;
  final String? logoUrl;

  Future<pw.ImageProvider?> _logo() async {
    if (logoUrl == null || logoUrl!.endsWith('.svg')) return null;
    try {
      return await networkImage(logoUrl!);
    } catch (_) {
      return null; // sin logo si no se puede descargar
    }
  }

  String _fileName(ReportQuery q, String ext) =>
      'reporte_${q.type.name}_${q.from.toIso8601String().substring(0, 10)}_${q.to.toIso8601String().substring(0, 10)}.$ext';

  Future<void> pdf(ReportQuery q, List<Map<String, dynamic>> rows) async {
    final cols = q.type.columns;
    final doc = pw.Document(title: 'Reporte de ${q.type.label}', author: centerName);
    const sage = PdfColor.fromInt(0xFF5E7D6F);
    final logo = await _logo();

    doc.addPage(
      pw.MultiPage(
        pageFormat: cols.length > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              if (logo != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 8), child: pw.Image(logo, height: 28)),
              pw.Text(centerName, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ]),
            pw.Text('Reporte de ${q.type.label}',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: sage)),
            pw.Text(
              'Período: ${Fmt.date(q.from)} al ${Fmt.date(q.to)}'
              '${q.type.grouped ? ' · Agrupado por ${q.group.label.toLowerCase()}' : ''}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Generado ${Fmt.date(DateTime.now())} ${Fmt.time(DateTime.now())} · '
              'Página ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: [for (final c in cols) c.label],
            data: [
              for (final r in rows) [for (final c in cols) c.format(r[c.key])],
              if (_totals(cols, rows) case final totals?) totals,
            ],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: sage),
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4EFE6)),
            cellAlignments: {
              for (var i = 0; i < cols.length; i++)
                i: cols[i].kind == ColumnKind.text || cols[i].kind == ColumnKind.date
                    ? pw.Alignment.centerLeft
                    : pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: _fileName(q, 'pdf'));
  }

  /// Fila de totales para columnas numéricas (null si no aplica).
  List<String>? _totals(List<ReportColumn> cols, List<Map<String, dynamic>> rows) {
    if (rows.length < 2 || !cols.any((c) => c.kind == ColumnKind.money || c.kind == ColumnKind.int)) return null;
    return [
      for (var i = 0; i < cols.length; i++)
        i == 0
            ? 'TOTAL'
            : (cols[i].kind == ColumnKind.money || cols[i].kind == ColumnKind.int) && cols[i].key != 'avg_ticket'
                ? cols[i].format(rows.fold<num>(0, (s, r) => s + ((r[cols[i].key] as num?) ?? 0)))
                : '',
    ];
  }

  Future<void> excel(ReportQuery q, List<Map<String, dynamic>> rows) async {
    final cols = q.type.columns;
    final book = xl.Excel.createExcel();
    final sheetName = q.type.label;
    book.rename(book.getDefaultSheet()!, sheetName);
    final sheet = book[sheetName];

    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.white,
      backgroundColorHex: xl.ExcelColor.fromHexString('#5E7D6F'),
    );

    sheet.appendRow([xl.TextCellValue('Reporte de ${q.type.label} · $centerName')]);
    sheet.appendRow([xl.TextCellValue('Período: ${Fmt.date(q.from)} al ${Fmt.date(q.to)}')]);
    sheet.appendRow([]);
    sheet.appendRow([for (final c in cols) xl.TextCellValue(c.label)]);
    for (var i = 0; i < cols.length; i++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3)).cellStyle = headerStyle;
      sheet.setColumnWidth(i, cols[i].kind == ColumnKind.text ? 28.0 : 16.0);
    }

    for (final r in rows) {
      sheet.appendRow([
        for (final c in cols)
          switch (c.kind) {
            ColumnKind.money || ColumnKind.percent => xl.DoubleCellValue(((r[c.key] as num?) ?? 0).toDouble()),
            ColumnKind.int => xl.IntCellValue(((r[c.key] as num?) ?? 0).toInt()),
            ColumnKind.date => r[c.key] == null
                ? xl.TextCellValue('')
                : () {
                    final d = DateTime.parse(r[c.key] as String);
                    return xl.DateCellValue(year: d.year, month: d.month, day: d.day);
                  }(),
            ColumnKind.text => xl.TextCellValue('${r[c.key] ?? ''}'),
          },
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    final name = _fileName(q, 'xlsx');

    if (kIsWeb) {
      await Share.shareXFiles([XFile.fromData(Uint8List.fromList(bytes), name: name)]);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Reporte de ${q.type.label}',
    );
  }
}
