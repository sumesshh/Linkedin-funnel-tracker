import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/services/csv_data.dart';

/// The QA case: October held the demo week "Oct 5–11" twice (5,018 reach each)
/// plus the real week "Oct 12–15" (3,878), so the monthly Reach total read
/// 13,900 while the weekly view showed each week correctly.
const _demoReach = 5018, _realReach = 3878;

Week _week(
  String id,
  DateTime start, {
  bool demo = false,
  DateTime? createdAt,
}) => Week(
  id: id,
  name: 'W $id',
  startDate: start,
  createdAt: createdAt,
  isDemo: demo,
);

List<Entry> _entries(String weekId, int reach) => [
  Entry(
    weekId: weekId,
    employeeId: 'e0',
    employeeName: 'Sumesh P S',
    values: {for (final m in metrics) m.key: m.key == 'reach' ? reach : 7},
  ),
];

/// October with the demo week duplicated under two document ids.
void _seedDuplicated() {
  final repo = Repository.instance;
  repo.employees = const [
    Employee(id: 'e0', name: 'Sumesh P S', order: 1, isActive: true),
  ];
  repo.allWeeks = [
    _week('dup_a', DateTime(2026, 10, 5),
        demo: true, createdAt: DateTime(2026, 10, 15, 6, 28)),
    _week('dup_b', DateTime(2026, 10, 5),
        demo: true, createdAt: DateTime(2026, 10, 15, 6, 31)),
    _week('real', DateTime(2026, 10, 12),
        createdAt: DateTime(2026, 10, 12, 9)),
  ];
  repo.weeks = repo.allWeeks;
  repo.entriesByWeek = {
    'dup_a': _entries('dup_a', _demoReach),
    'dup_b': _entries('dup_b', _demoReach),
    'real': _entries('real', _realReach),
  };
}

void main() {
  group('dedupeWeeks', () {
    test('collapses duplicate documents for one start date', () {
      final weeks = dedupeWeeks([
        _week('a', DateTime(2026, 10, 5), demo: true),
        _week('b', DateTime(2026, 10, 5), demo: true),
        _week('c', DateTime(2026, 10, 12)),
      ]);
      expect(weeks.map((w) => w.startDate), [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
      ]);
    });

    test('keeps the real week over a demo week on the same date', () {
      for (final order in [
        [_week('demo', DateTime(2026, 10, 5), demo: true), _week('real', DateTime(2026, 10, 5))],
        [_week('real', DateTime(2026, 10, 5)), _week('demo', DateTime(2026, 10, 5), demo: true)],
      ]) {
        expect(dedupeWeeks(order).single.id, 'real');
      }
    });

    test('keeps the oldest of two demo copies, whatever the document order',
        () {
      final first = _week('b', DateTime(2026, 10, 5),
          demo: true, createdAt: DateTime(2026, 10, 15, 6, 28));
      final second = _week('a', DateTime(2026, 10, 5),
          demo: true, createdAt: DateTime(2026, 10, 15, 6, 31));
      expect(dedupeWeeks([first, second]).single.id, 'b');
      expect(dedupeWeeks([second, first]).single.id, 'b');
    });

    test('is stable when duplicates carry no createdAt', () {
      final weeks = [
        _week('zz', DateTime(2026, 10, 5), demo: true),
        _week('aa', DateTime(2026, 10, 5), demo: true),
      ];
      expect(dedupeWeeks(weeks).single.id, 'aa');
      expect(dedupeWeeks(weeks.reversed).single.id, 'aa');
    });

    test('a week is identified by its local start date, not the UTC one', () {
      // IST midnight on 1 Oct serialises as 30 Sep 18:30Z. Keyed in UTC this
      // week would fall into September.
      final w = _week('ist', DateTime(2026, 10, 1));
      expect(weekStartKey(w), DateTime(2026, 10, 1));
      expect(dedupeWeeks([w]).single.startDate.month, 10);
    });

    test('sorts oldest first regardless of input order', () {
      final weeks = dedupeWeeks([
        _week('c', DateTime(2026, 10, 12)),
        _week('a', DateTime(2026, 9, 28)),
        _week('b', DateTime(2026, 10, 5)),
      ]);
      expect(weeks.map((w) => w.id), ['a', 'b', 'c']);
    });
  });

  group('monthly totals', () {
    test('duplicate week documents do not inflate a monthly sum', () {
      _seedDuplicated();
      final october = Repository.instance.monthlyTotals.single;
      expect(october.month, DateTime(2026, 10));
      expect(october.totals['reach'], _demoReach + _realReach); // 8,896
      expect(october.totals['reach'], isNot(2 * _demoReach + _realReach));
      expect(october.weekCount, 2);
    });

    test('monthly totals equal the sum of the weekly totals, every month',
        () {
      _seedDuplicated();
      final repo = Repository.instance;
      repo.allWeeks = [
        ...repo.allWeeks,
        _week('sep', DateTime(2026, 9, 28), demo: true),
        _week('sep_dup', DateTime(2026, 9, 28), demo: true),
      ];
      repo.weeks = repo.allWeeks;
      repo.entriesByWeek['sep'] = _entries('sep', 4200);
      repo.entriesByWeek['sep_dup'] = _entries('sep_dup', 4200);

      final weekly = dedupeWeeks(repo.weeks);
      for (final month in repo.monthlyTotals) {
        final weeksInMonth = weekly.where((w) =>
            w.startDate.year == month.month.year &&
            w.startDate.month == month.month.month);
        expect(weeksInMonth.length, month.weekCount);
        for (final m in metrics) {
          final sum = weeksInMonth.fold<int>(
              0, (t, w) => t + repo.totalsFor(w.id)[m.key]!);
          expect(month.totals[m.key], sum,
              reason: '${m.label} in ${month.month}');
        }
      }
    });

    test('a month holding only duplicates of one week counts it once', () {
      final repo = Repository.instance;
      repo.employees = const [
        Employee(id: 'e0', name: 'Sumesh P S', order: 1, isActive: true),
      ];
      repo.allWeeks = [
        for (var i = 0; i < 5; i++)
          _week('c$i', DateTime(2026, 7, 6),
              demo: true, createdAt: DateTime(2026, 10, 15, 6, i)),
      ];
      repo.weeks = repo.allWeeks;
      repo.entriesByWeek = {
        for (var i = 0; i < 5; i++) 'c$i': _entries('c$i', 1000),
      };
      final july = repo.monthlyTotals.single;
      expect(july.weekCount, 1);
      expect(july.totals['reach'], 1000);
    });
  });

  group('exports', () {
    test('monthly CSV rows are not inflated by duplicates', () {
      _seedDuplicated();
      final rows = monthlyTotalsRows();
      final reachCol = rows.first.indexOf('Reach / Impressions');
      expect(rows.length, 2); // header + October
      expect(rows[1][reachCol], _demoReach + _realReach);
      expect(rows[1][1], 2); // "Weeks"
      expect(rows[1].last, 1); // "Demo Weeks"
    });

    test('weekly CSV lists each week once and agrees with the monthly row',
        () {
      _seedDuplicated();
      final weekly = weeklyTotalsRows().skip(1).toList();
      final reachCol = weeklyTotalsRows().first.indexOf('Reach / Impressions');
      expect(weekly.length, 2);
      expect(
        weekly.fold<int>(0, (t, r) => t + (r[reachCol] as int)),
        monthlyTotalsRows()[1][reachCol],
      );
    });

    test('raw employee-level rows skip the duplicate week', () {
      _seedDuplicated();
      final rows = rawRows().skip(1).toList();
      expect(rows.length, 2); // one employee × two real weeks
      expect(rows.map((r) => r[0]), isNot(contains('W dup_b')));
    });
  });
}
