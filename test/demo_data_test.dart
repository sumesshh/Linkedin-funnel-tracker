import 'dart:convert' show LineSplitter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/demo_data.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/services/csv_data.dart';
import 'package:linkedin_dashboard/widgets/common.dart' show fmt;
import 'package:linkedin_dashboard/widgets/metric_chart.dart';

const _names = [
  'Sumesh P S',
  'Smrithy S',
  'Rajeev R E',
  'Teena Joseph',
  'Abhinav',
  'Pooja',
  'Jhony Francis',
  'Prince Thomas',
];

/// 22 Monday-starting demo weeks spanning Jun–Oct 2026, plus one real week.
final _starts = [
  for (var i = 0; i < 22; i++) DateTime(2026, 5, 25 + 7 * i),
];

/// Loads demo weeks (and one real week) into the repository in memory,
/// mirroring what seedMockData writes to Firestore.
void _seed() {
  final repo = Repository.instance;
  repo.employees = [
    for (var i = 0; i < _names.length; i++)
      Employee(id: 'e$i', name: _names[i], order: i + 1, isActive: true),
  ];
  repo.weeks = [
    for (final (i, s) in _starts.indexed)
      Week(id: 'd$i', name: 'Demo $i', startDate: s, isDemo: true),
    Week(id: 'real', name: 'Real week', startDate: DateTime(2026, 10, 26)),
  ];
  repo.entriesByWeek = {
    for (final (i, s) in _starts.indexed)
      'd$i': [
        for (var e = 0; e < _names.length; e++)
          Entry(
            weekId: 'd$i',
            employeeId: 'e$e',
            employeeName: _names[e],
            values: demoValues(_names[e], s, progress: i / (_starts.length - 1)),
          ),
      ],
    'real': [
      Entry(
        weekId: 'real',
        employeeId: 'e0',
        employeeName: _names[0],
        values: {for (final m in metrics) m.key: 1234},
      ),
    ],
  };
}

void main() {
  group('stale demo data', () {
    test('old oversized records are detected, new ones are not', () {
      _seed();
      final repo = Repository.instance;
      expect(repo.staleDemoWeeks, isEmpty);
      // An old-generator week: 4,000+ reach for one employee.
      repo.entriesByWeek['d0'] = [
        Entry(weekId: 'd0', employeeId: 'e0', employeeName: 'Sumesh P S', values: {
          for (final m in metrics) m.key: m.key == 'reach' ? 4100 : 5,
        }),
      ];
      expect(repo.staleDemoWeeks.map((w) => w.id), ['d0']);
      // Real weeks are never flagged, whatever they contain.
      repo.entriesByWeek['real'] = [
        Entry(weekId: 'real', employeeId: 'e0', employeeName: 'x', values: {'reach': 9999}),
      ];
      expect(repo.staleDemoWeeks.map((w) => w.id), ['d0']);
    });

    test('diagnostics lists every week with records, reach and yMax', () {
      _seed();
      final lines = const LineSplitter()
          .convert(Repository.instance.diagnostics())
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines.length, _starts.length + 1);
      expect(lines.first, contains('8 records'));
      expect(lines.last, contains('[REAL]'));
      // ignore: avoid_print
      print(lines.take(3).join(String.fromCharCode(10)));
    });

    test('planDemoWeeks stops before the earliest real week, no overlap', () {
      final real = DateTime(2026, 9, 21);
      final plan = planDemoWeeks([real], DateTime(2026, 10, 15));
      expect(plan.first.start.weekday, DateTime.monday);
      expect(plan.every((w) => w.start.isBefore(real)), isTrue);
      expect(plan.last.start, DateTime(2026, 9, 14));
      expect(plan.map((w) => w.start).toSet().length, plan.length);
      expect(plan.first.progress, 0);
      expect(plan.last.progress, 1);
    });
  });

  group('demo values', () {
    test('every employee/week stays inside its configured range', () {
      for (final name in _names) {
        for (final (i, s) in _starts.indexed) {
          final v = demoValues(name, s, progress: i / (_starts.length - 1));
          expect(v.keys.toSet(), {for (final m in metrics) m.key});
          for (final MapEntry(key: k, value: (lo, hi)) in demoRanges.entries) {
            expect(v[k], inInclusiveRange(lo, hi), reason: '$name $s $k');
          }
          expect(v['reach'], lessThan(1000));
        }
      }
    });

    test('deterministic: same inputs give the same numbers', () {
      final s = DateTime(2026, 7, 6);
      expect(demoValues('Pooja', s), demoValues('Pooja', s));
    });

    test('values differ between employees and between weeks', () {
      final byEmployee = {
        for (final n in _names) demoValues(n, _starts.first).toString(),
      };
      expect(byEmployee.length, _names.length);
      final byWeek = {
        for (final s in _starts) demoValues('Abhinav', s).toString(),
      };
      expect(byWeek.length, _starts.length);
    });

    test('Prince Thomas (repost-only) always has 0 posts', () {
      for (final s in _starts) {
        expect(demoValues('Prince Thomas', s)['posts'], 0);
      }
      expect(
        _starts.any((s) => demoValues('Sumesh P S', s)['posts']! > 0),
        isTrue,
      );
    });
  });

  group('aggregation', () {
    setUp(_seed);

    test('weekly totals equal the sum of employee records', () {
      final repo = Repository.instance;
      for (final w in repo.weeks) {
        final totals = repo.totalsFor(w.id);
        for (final m in metrics) {
          final sum = repo.entriesFor(w.id).fold<int>(0, (a, e) => a + e[m.key]);
          expect(totals[m.key], sum);
        }
      }
    });

    test('combined weekly reach is not capped below 1,000', () {
      final repo = Repository.instance;
      final maxReach = repo.weeks
          .where((w) => w.isDemo)
          .map((w) => repo.totalsFor(w.id)['reach']!)
          .reduce(math.max);
      expect(maxReach, greaterThan(2000));
    });

    test('monthly totals use only weeks starting in that month', () {
      final repo = Repository.instance;
      for (final r in repo.monthlyTotals) {
        final inMonth = repo.weeks.where((w) =>
            w.startDate.year == r.month.year &&
            w.startDate.month == r.month.month);
        expect(r.weekCount, inMonth.length);
        for (final m in metrics) {
          final sum = inMonth.fold<int>(
              0, (a, w) => a + repo.totalsFor(w.id)[m.key]!);
          expect(r.totals[m.key], sum, reason: '${r.month} ${m.key}');
        }
      }
    });

    test('axis never clips weekly or monthly points', () {
      final repo = Repository.instance;
      final weekly = [for (final w in repo.weeks) repo.totalsFor(w.id)];
      final monthly = [for (final r in repo.monthlyTotals) r.totals];
      for (final (series, period) in [
        (weekly, ChartPeriod.weekly),
        (monthly, ChartPeriod.monthly),
      ]) {
        final max = series.expand((v) => v.values).reduce(math.max);
        final s = axisScale(max, period);
        expect(s.maxY, greaterThanOrEqualTo(max));
        expect(s.maxY % s.interval, 0);
        if (period == ChartPeriod.weekly) expect(s.interval % 200, 0);
      }
    });
  });

  group('CSV', () {
    setUp(_seed);

    test('employee-level rows hold numeric individual values', () {
      final repo = Repository.instance;
      final rows = rawRows();
      expect(rows.first.last, 'Data');
      expect(rows.length, 1 + _starts.length * _names.length + 1);
      final first = rows[1];
      final entry = repo.entriesFor('d0').first;
      expect(first.sublist(4, 4 + metrics.length),
          [for (final m in metrics) entry[m.key]]);
      expect(first.sublist(4, 4 + metrics.length), everyElement(isA<int>()));
      expect(first.last, demoLabel);
      expect(rows.last.last, actualLabel);
    });

    test('weekly summary rows equal week totals', () {
      final repo = Repository.instance;
      final rows = weeklyTotalsRows();
      for (final (i, w) in repo.weeks.indexed) {
        final row = rows[i + 1];
        expect(row.sublist(2, 2 + metrics.length),
            [for (final m in metrics) repo.totalsFor(w.id)[m.key]]);
        expect(row.last, w.isDemo ? demoLabel : actualLabel);
      }
    });

    test('monthly summary rows equal month totals', () {
      final repo = Repository.instance;
      final rows = monthlyTotalsRows();
      final months = repo.monthlyTotals;
      expect(rows.length, 1 + months.length);
      for (final (i, r) in months.indexed) {
        expect(rows[i + 1].sublist(2, 2 + metrics.length),
            [for (final m in metrics) r.totals[m.key]]);
      }
      // October has 3 demo weeks (5, 12, 19) and the real week.
      final oct = rows.firstWhere((r) => r[0] == 'Oct 2026');
      expect(oct[1], 4);
      expect(oct.last, 3);
    });
  });

  group('chart', () {
    Future<void> pump(WidgetTester t, Widget child) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child))));
      await t.pumpAndSettle();
    }

    testWidgets('empty data renders without errors', (t) async {
      await pump(t, const MetricLineChart(labels: [], values: []));
      expect(find.text('No data yet'), findsOneWidget);
    });

    testWidgets('all-zero data renders without errors', (t) async {
      for (final period in ChartPeriod.values) {
        await pump(
          t,
          MetricLineChart(
            key: ValueKey(period),
            labels: const ['A', 'B'],
            values: [
              for (var i = 0; i < 2; i++) {for (final m in metrics) m.key: 0},
            ],
            period: period,
          ),
        );
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('weekly labels step by 200, monthly by a nice interval',
        (t) async {
      _seed();
      final repo = Repository.instance;
      final weeks = repo.weeks.take(4).toList();
      await pump(
        t,
        MetricLineChart(
          labels: [for (final w in weeks) w.name],
          values: [for (final w in weeks) repo.totalsFor(w.id)],
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.text('0'), findsWidgets);

      final months = repo.monthlyTotals;
      await pump(
        t,
        MetricLineChart(
          labels: [for (final r in months) monthLabel.format(r.month)],
          values: [for (final r in months) r.totals],
          period: ChartPeriod.monthly,
        ),
      );
      expect(t.takeException(), isNull);
      final max = months.expand((r) => r.totals.values).reduce(math.max);
      final s = axisScale(max, ChartPeriod.monthly);
      expect(find.text(fmt(s.maxY)), findsOneWidget);
    });
  });
}
