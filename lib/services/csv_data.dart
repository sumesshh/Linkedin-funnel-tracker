import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models.dart';

final day = DateFormat('yyyy-MM-dd');
final monthLabel = DateFormat('MMM yyyy');

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// RFC 4180 CSV with a UTF-8 BOM so Excel also reads "–" and names correctly.
String toCsv(List<List<Object?>> rows) =>
    '﻿${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';

List<String> get _metricHeaders => [for (final m in metrics) m.label];

/// The weeks every export is built from: one per start date, so a duplicated
/// week document can never be counted twice in a summary row.
List<Week> get _weeks => dedupeWeeks(Repository.instance.weeks);

/// Value of the trailing "Data" column: generated demo rows vs real numbers.
const demoLabel = 'DEMO DATA', actualLabel = 'Actual';
String _source(Week w) => w.isDemo ? demoLabel : actualLabel;

/// One row per week: all-employee totals. Chart-ready in Google Sheets.
List<List<Object?>> weeklyTotalsRows() {
  final repo = Repository.instance;
  return [
    ['Week', 'Start Date', ..._metricHeaders, 'Data'],
    for (final w in _weeks)
      [
        w.name,
        day.format(w.startDate),
        for (final m in metrics) repo.totalsFor(w.id)[m.key],
        _source(w),
      ],
  ];
}

/// One row per month: all-employee totals. "Demo Weeks" counts how many of
/// the month's weeks are generated DEMO DATA.
List<List<Object?>> monthlyTotalsRows() {
  final repo = Repository.instance;
  int demoWeeks(DateTime month) => _weeks
      .where((w) =>
          w.isDemo &&
          w.startDate.year == month.year &&
          w.startDate.month == month.month)
      .length;
  return [
    ['Month', 'Weeks', ..._metricHeaders, 'Demo Weeks'],
    for (final r in repo.monthlyTotals)
      [
        monthLabel.format(r.month),
        r.weekCount,
        for (final m in metrics) r.totals[m.key],
        demoWeeks(r.month),
      ],
  ];
}

/// One row per employee per week — the full dataset.
List<List<Object?>> rawRows() {
  final repo = Repository.instance;
  return [
    ['Week', 'Start Date', 'Month', 'Employee', ..._metricHeaders, 'Data'],
    for (final w in _weeks)
      for (final e in repo.entriesFor(w.id))
        [
          w.name,
          day.format(w.startDate),
          monthLabel.format(w.startDate),
          e.employeeName,
          for (final m in metrics) e[m.key],
          _source(w),
        ],
  ];
}
