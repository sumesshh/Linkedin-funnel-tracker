import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/repository.dart';
import '../models.dart';
import '../widgets/metric_chart.dart' show gridInterval, compact;

final _num = NumberFormat.decimalPattern('en_IN');
const _gray = PdfColor.fromInt(0xFF757575);
const _dark = PdfColor.fromInt(0xFF212121);
const _divider = PdfColor.fromInt(0xFFEEEEEE);
const _headerBg = PdfColor.fromInt(0xFFF8F9FA);
const _blue = PdfColor.fromInt(0xFF4285F4);

PdfColor _pdfColor(Metric m) => PdfColor.fromInt(m.color.toARGB32());

/// Months (first day) that contain at least one week, newest first.
List<DateTime> reportMonths(List<Week> weeks) {
  final set = {for (final w in weeks) DateTime(w.startDate.year, w.startDate.month)};
  return set.toList()..sort((a, b) => b.compareTo(a));
}

/// Builds the monthly report for weeks whose start date falls in [month].
Future<Uint8List> buildMonthlyReport(DateTime month) async {
  final repo = Repository.instance;
  final weeks = repo.weeks
      .where((w) =>
          w.startDate.year == month.year && w.startDate.month == month.month)
      .toList();
  final monthLabel = DateFormat('MMMM yyyy').format(month);

  pw.ThemeData theme;
  try {
    theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
    );
  } catch (_) {
    theme = pw.ThemeData(); // offline: built-in Helvetica
  }

  final doc = pw.Document(
    title: 'LinkedIn Analytics Report — $monthLabel',
    author: 'Rextech Studios',
    theme: theme,
  );

  final weekTotals = {for (final w in weeks) w.id: repo.totalsFor(w.id)};
  final monthTotals = {for (final m in metrics) m.key: 0};
  for (final t in weekTotals.values) {
    for (final m in metrics) {
      monthTotals[m.key] = monthTotals[m.key]! + t[m.key]!;
    }
  }

  // Per-employee monthly totals, keyed by employee id.
  final byEmployee = <String, (String, Map<String, int>)>{};
  for (final w in weeks) {
    for (final e in repo.entriesFor(w.id)) {
      final cur = byEmployee[e.employeeId] ??=
          (e.employeeName, {for (final m in metrics) m.key: 0});
      for (final m in metrics) {
        cur.$2[m.key] = cur.$2[m.key]! + e[m.key];
      }
    }
  }

  Week? bestWeek;
  for (final w in weeks) {
    if (bestWeek == null ||
        weekTotals[w.id]!['reach']! > weekTotals[bestWeek.id]!['reach']!) {
      bestWeek = w;
    }
  }
  (String, Map<String, int>)? bestEmployee;
  for (final e in byEmployee.values) {
    if (bestEmployee == null || e.$2['reach']! > bestEmployee.$2['reach']!) {
      bestEmployee = e;
    }
  }

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    theme: theme,
  );

  pw.Widget footer(pw.Context ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'LinkedIn Analytics Report — $monthLabel  ·  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _gray),
        ),
      );

  // Page 1 — cover
  doc.addPage(pw.Page(
    pageTheme: pageTheme,
    build: (_) => pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: 60, height: 4, color: _blue),
        pw.SizedBox(height: 24),
        pw.Text('LinkedIn Analytics Report — $monthLabel',
            style: pw.TextStyle(
                fontSize: 28, fontWeight: pw.FontWeight.bold, color: _dark)),
        pw.SizedBox(height: 16),
        pw.Text('Rextech Studios',
            style: const pw.TextStyle(fontSize: 18, color: _gray)),
        pw.SizedBox(height: 8),
        pw.Text('Generated ${DateFormat('d MMMM yyyy').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 12, color: _gray)),
        pw.SizedBox(height: 4),
        pw.Text(
            '${weeks.length} week${weeks.length == 1 ? '' : 's'} · '
            '${byEmployee.length} employee${byEmployee.length == 1 ? '' : 's'}',
            style: const pw.TextStyle(fontSize: 12, color: _gray)),
      ],
    ),
  ));

  // Page 2 — monthly summary
  doc.addPage(pw.Page(
    pageTheme: pageTheme,
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('Monthly Summary'),
        pw.Text('Totals across all ${weeks.length} weeks in $monthLabel',
            style: const pw.TextStyle(color: _gray, fontSize: 11)),
        pw.SizedBox(height: 16),
        _table(
          ['Metric', 'Total'],
          [for (final m in metrics) [m.label, _num.format(monthTotals[m.key])]],
          numericFrom: 1,
        ),
        pw.SizedBox(height: 28),
        _heading('Highlights', size: 16),
        _highlight(
          'Best week (highest total reach)',
          bestWeek == null
              ? '—'
              : '${bestWeek.name} — ${_num.format(weekTotals[bestWeek.id]!['reach'])} reach',
        ),
        _highlight(
          'Best employee (highest total reach)',
          bestEmployee == null
              ? '—'
              : '${bestEmployee.$1} — ${_num.format(bestEmployee.$2['reach'])} reach',
        ),
        _highlight(
          'Total enquiries (Academy + Studios)',
          _num.format(monthTotals['academyEnquiries']! +
              monthTotals['studiosEnquiries']!),
        ),
        pw.Spacer(),
        footer(ctx),
      ],
    ),
  ));

  // Page 3 — weekly totals chart + numbers table
  doc.addPage(pw.Page(
    pageTheme: pageTheme.copyWith(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30)),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('Weekly Totals — All Employees'),
        _legend(),
        pw.SizedBox(height: 8),
        pw.SizedBox(
          height: 230,
          child: _chart(
            [for (final w in weeks) w.name],
            [for (final w in weeks) weekTotals[w.id]!],
          ),
        ),
        pw.SizedBox(height: 16),
        _metricTable(
          'Week',
          [for (final w in weeks) (w.name, weekTotals[w.id]!)],
          total: monthTotals,
        ),
        pw.Spacer(),
        footer(ctx),
      ],
    ),
  ));

  // Page 4+ — one section per week
  for (final w in weeks) {
    final entries = repo.entriesFor(w.id);
    doc.addPage(pw.Page(
      pageTheme: pageTheme.copyWith(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(30)),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _heading('Week: ${w.name}'),
          if (entries.isEmpty)
            pw.Text('No data entered for this week.',
                style: const pw.TextStyle(color: _gray))
          else ...[
            _metricTable(
              'Employee',
              [for (final e in entries) (e.employeeName, e.values)],
              total: weekTotals[w.id],
            ),
            pw.SizedBox(height: 16),
            _legend(),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: _chart(
                [for (final e in entries) e.employeeName],
                [for (final e in entries) e.values],
              ),
            ),
          ],
          if (entries.isEmpty) pw.Spacer(),
          footer(ctx),
        ],
      ),
    ));
  }

  // Last — raw data table (spans pages as needed)
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme.copyWith(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30)),
    footer: footer,
    build: (_) => [
      _heading('Raw Data'),
      pw.Text(
          'One row per employee per week. Copy this table into Google Sheets '
          'as a backup.',
          style: const pw.TextStyle(color: _gray, fontSize: 10)),
      pw.SizedBox(height: 12),
      _table(
        ['Week', 'Employee', for (final m in metrics) m.short],
        [
          for (final w in weeks)
            for (final e in repo.entriesFor(w.id))
              [
                w.name,
                e.employeeName,
                for (final m in metrics) '${e[m.key]}',
              ],
        ],
        numericFrom: 2,
        fontSize: 9,
      ),
    ],
  ));

  return doc.save();
}

pw.Widget _heading(String text, {double size = 20}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: size, fontWeight: pw.FontWeight.bold, color: _dark)),
    );

pw.Widget _highlight(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: _gray)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold, color: _dark)),
        ],
      ),
    );

pw.Widget _legend() => pw.Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final m in metrics)
          pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                    color: _pdfColor(m), shape: pw.BoxShape.circle)),
            pw.SizedBox(width: 4),
            pw.Text(m.label,
                style: const pw.TextStyle(fontSize: 8, color: _gray)),
          ]),
      ],
    );

pw.Widget _chart(List<String> labels, List<Map<String, int>> values) {
  if (labels.isEmpty) return pw.SizedBox();
  final maxValue = [
    for (final v in values)
      for (final m in metrics) v[m.key] ?? 0,
  ].fold<int>(0, math.max);
  final step = gridInterval(maxValue);
  final maxY = math.max(step, (maxValue / step).ceil() * step);
  final single = labels.length == 1;

  return pw.Chart(
    grid: pw.CartesianGrid(
      xAxis: pw.FixedAxis.fromStrings(
        labels,
        marginStart: 20,
        marginEnd: 20,
        textStyle: const pw.TextStyle(fontSize: 7, color: _gray),
        color: _divider,
      ),
      yAxis: pw.FixedAxis<num>(
        [for (var y = 0.0; y <= maxY + 0.1; y += step) y],
        format: compact,
        divisions: true,
        divisionsColor: _divider,
        divisionsWidth: 0.5,
        textStyle: const pw.TextStyle(fontSize: 7, color: _gray),
        color: _divider,
      ),
    ),
    datasets: [
      for (final m in metrics)
        pw.LineDataSet(
          data: [
            for (var i = 0; i < labels.length; i++)
              pw.PointChartValue(i.toDouble(), (values[i][m.key] ?? 0).toDouble()),
          ],
          color: _pdfColor(m),
          lineWidth: 1.6,
          isCurved: true,
          smoothness: 0.35,
          drawPoints: single,
          pointSize: 2.5,
        ),
    ],
  );
}

pw.Widget _metricTable(
  String firstColumn,
  List<(String, Map<String, int>)> rows, {
  Map<String, int>? total,
}) =>
    _table(
      [firstColumn, for (final m in metrics) m.short],
      [
        for (final (name, v) in rows)
          [name, for (final m in metrics) _num.format(v[m.key] ?? 0)],
        if (total != null)
          ['Total', for (final m in metrics) _num.format(total[m.key] ?? 0)],
      ],
      numericFrom: 1,
      boldLastRow: total != null,
    );

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  int numericFrom = 1,
  bool boldLastRow = false,
  double fontSize = 9.5,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _divider, width: 0.5),
        bottom: pw.BorderSide(color: _divider, width: 0.5)),
    headerDecoration: const pw.BoxDecoration(color: _headerBg),
    headerStyle: pw.TextStyle(
        fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: _gray),
    cellStyle: pw.TextStyle(fontSize: fontSize, color: _dark),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    headerAlignments: {
      for (var i = 0; i < headers.length; i++)
        i: i < numericFrom ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
    },
    cellAlignments: {
      for (var i = 0; i < headers.length; i++)
        i: i < numericFrom ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
    },
    rowDecoration: null,
    cellDecoration: boldLastRow
        ? (index, data, rowNum) => rowNum == rows.length
            ? const pw.BoxDecoration(color: _headerBg)
            : const pw.BoxDecoration()
        : null,
  );
}

Future<void> downloadMonthlyReport(DateTime month) async {
  final bytes = await buildMonthlyReport(month);
  await Printing.sharePdf(
    bytes: bytes,
    filename:
        'LinkedIn-Report-${DateFormat('yyyy-MM').format(month)}.pdf',
  );
}
