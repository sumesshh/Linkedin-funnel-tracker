import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/services/csv_data.dart';
import 'package:linkedin_dashboard/services/pdf_report.dart';
import 'package:linkedin_dashboard/widgets/metric_chart.dart';

const _names = ['Sumesh P S', 'Anjali R', 'Rahul Menon'];

/// 3 weeks in September + 1 in October, 3 employees each.
void _seed() {
  final repo = Repository.instance;
  repo.employees = [
    for (var i = 0; i < _names.length; i++)
      Employee(id: 'e$i', name: _names[i], order: i + 1, isActive: true),
  ];
  repo.weeks = [
    for (final (w, start) in [
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 21),
      DateTime(2026, 10, 5),
    ].indexed)
      Week(id: 'w$w', name: suggestName(start), startDate: start),
  ];
  repo.entriesByWeek = {
    for (final w in repo.weeks)
      w.id: [
        for (var i = 0; i < _names.length; i++)
          Entry(
            weekId: w.id,
            employeeId: 'e$i',
            employeeName: _names[i],
            values: {
              for (final (k, m) in metrics.indexed)
                m.key: (k + 1) * (i + 2) * (w.startDate.day + 3),
            },
          ),
      ],
  };
}

String suggestName(DateTime d) => 'Week of ${d.month}/${d.day}';

void main() {
  test('gridInterval keeps 200 for small values and widens for large ones', () {
    expect(gridInterval(0), 200);
    expect(gridInterval(1800), 200);
    expect(gridInterval(20000) % 200, 0);
    expect(20000 / gridInterval(20000), lessThanOrEqualTo(10));
  });

  test('sumEntries and sortEntries', () {
    final emps = [
      const Employee(id: 'b', name: 'B', order: 1, isActive: true),
      const Employee(id: 'a', name: 'A', order: 2, isActive: true),
    ];
    Entry e(String id, int posts) => Entry(
        weekId: 'w', employeeId: id, employeeName: id.toUpperCase(),
        values: {'posts': posts});
    final sorted = sortEntries([e('gone', 1), e('a', 2), e('b', 3)], emps);
    expect(sorted.map((x) => x.employeeId), ['b', 'a', 'gone']);
    expect(sumEntries(sorted)['posts'], 6);
    expect(sumEntries(sorted)['reach'], 0);
  });

  test('monthly totals group weeks by start month', () {
    _seed();
    final repo = Repository.instance;
    final months = repo.monthlyTotals;
    expect(months.map((m) => m.month), [DateTime(2026, 9), DateTime(2026, 10)]);
    expect(months.map((m) => m.weekCount), [3, 1]);
    final sept = repo.weeks
        .take(3)
        .fold<int>(0, (s, w) => s + repo.totalsFor(w.id)['reach']!);
    expect(months.first.totals['reach'], sept);
  });

  test('CSV rows and escaping', () {
    _seed();
    expect(weeklyTotalsRows().length, 1 + 4);
    expect(weeklyTotalsRows()[1].take(2), ['Week of 9/7', '2026-09-07']);
    expect(monthlyTotalsRows().map((r) => r[0]), ['Month', 'Sep 2026', 'Oct 2026']);
    expect(rawRows().length, 1 + 4 * 3);
    expect(rawRows()[1].take(4),
        ['Week of 9/7', '2026-09-07', 'Sep 2026', 'Sumesh P S']);
    expect(toCsv([
      ['a,b', 'say "hi"', 3],
    ]), '﻿"a,b","say ""hi""",3\r\n');
  });

  test('monthly report builds', () async {
    _seed();
    final bytes = await buildMonthlyReport(DateTime(2026, 9));
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
