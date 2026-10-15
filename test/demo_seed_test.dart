import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/demo_data.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';

/// The live shape: 7 active employees, one real week starting Mon 12 Oct 2026,
/// "today" being 15 Oct 2026. The 5-month window then plans 22 demo weeks
/// (11 May – 5 Oct), which is exactly what production holds.
const _names = [
  'Sumesh P S',
  'Smrithy S',
  'Rajeev R E',
  'Teena Joseph',
  'Abhinav',
  'Pooja',
  'Prince Thomas',
];
final _today = DateTime(2026, 10, 15);
final _realStart = DateTime(2026, 10, 12);
const _realWeekId = 'hnKSssqhFe2xlweXrAD5'; // the real "Oct 12–15" document
const _expectedWeeks = 22;
const _expectedEntries = _expectedWeeks * 7;

/// The real week as stored, plus one employee's real numbers, so a seed that
/// overwrote real data would show up as a diff.
const _realEntry = {
  'employeeName': 'Sumesh P S',
  'posts': 80,
  'comments': 77,
  'likes': 788,
  'reach': 3878,
  'profileViews': 12,
  'inboundDMs': 3,
  'academyEnquiries': 6666,
  'studiosEnquiries': 1,
};

late FakeFirebaseFirestore db;
late Repository repo;

Future<void> _setUp({bool withRealWeek = true}) async {
  db = FakeFirebaseFirestore();
  repo = Repository.instance..useFirestoreForTests(db);
  repo.employees = [
    for (final (i, n) in _names.indexed)
      Employee(id: 'e$i', name: n, order: i + 1, isActive: true),
  ];
  if (withRealWeek) {
    await db.collection('weeks').doc(_realWeekId).set({
      'name': 'Oct 12–15',
      'startDate': Timestamp.fromDate(_realStart),
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 12, 9)),
    });
    await db
        .collection('weeks')
        .doc(_realWeekId)
        .collection('entries')
        .doc('e0')
        .set(_realEntry);
    repo.allWeeks = [
      Week(
        id: _realWeekId,
        name: 'Oct 12–15',
        startDate: _realStart,
        createdAt: DateTime(2026, 10, 12, 9),
      ),
    ];
    repo.weeks = repo.allWeeks;
  }
}

/// Every week document in the fake, as (id, isDemo, startDate).
Future<List<({String id, bool demo, DateTime start})>> _weeks() async {
  final snap = await db.collection('weeks').get();
  return [
    for (final d in snap.docs)
      (
        id: d.id,
        demo: d.data()['mock'] == true,
        start: (d.data()['startDate'] as Timestamp).toDate(),
      ),
  ];
}

Future<int> _entryCount(String weekId) async =>
    (await db.collection('weeks').doc(weekId).collection('entries').get())
        .docs
        .length;

Future<int> _demoEntryCount() async {
  var n = 0;
  for (final w in await _weeks()) {
    if (w.demo) n += await _entryCount(w.id);
  }
  return n;
}

/// Mirrors the repository's snapshot listener, which is not running in tests.
Future<void> _refresh() async {
  final snap =
      await db.collection('weeks').orderBy('startDate').get();
  repo.allWeeks = snap.docs.map(Week.fromDoc).toList();
  repo.weeks = dedupeWeeks(repo.allWeeks);
}

void main() {
  group('idempotent seed', () {
    test('running it three times leaves exactly 22 weeks and 154 entries',
        () async {
      await _setUp();
      for (var run = 1; run <= 3; run++) {
        final n = await repo.seedMockData(today: _today);
        await _refresh();
        expect(n, _expectedWeeks, reason: 'run $run returned a plan length');

        final weeks = await _weeks();
        final demo = weeks.where((w) => w.demo).toList();
        expect(demo.length, _expectedWeeks, reason: 'demo weeks after run $run');
        expect(weeks.length, _expectedWeeks + 1,
            reason: 'demo weeks + the real week after run $run');
        expect(await _demoEntryCount(), _expectedEntries,
            reason: 'demo entries after run $run');
      }
    });

    test('every demo document id is derived from its week start', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      for (final w in (await _weeks()).where((w) => w.demo)) {
        expect(w.id, Repository.demoWeekId(w.start));
        expect(w.id, startsWith('demo_'));
      }
      expect((await _weeks()).map((w) => w.id), contains('demo_2026-10-05'));
    });

    test('ids and values are identical across runs', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      Future<Map<String, Map<String, dynamic>>> snapshot() async {
        final out = <String, Map<String, dynamic>>{};
        for (final w in (await _weeks()).where((w) => w.demo)) {
          final entries = await db
              .collection('weeks')
              .doc(w.id)
              .collection('entries')
              .get();
          for (final e in entries.docs) {
            out['${w.id}/${e.id}'] = {
              for (final m in metrics) m.key: e.data()[m.key],
            };
          }
        }
        return out;
      }

      final first = await snapshot();
      await repo.seedMockData(today: _today);
      expect(await snapshot(), first);
      expect(first.length, _expectedEntries);
    });

    test('generated values stay inside the documented demo limits', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      for (final w in (await _weeks()).where((w) => w.demo)) {
        final entries =
            await db.collection('weeks').doc(w.id).collection('entries').get();
        for (final e in entries.docs) {
          final values = {
            for (final m in metrics) m.key: e.data()[m.key] as int,
          };
          expect(withinDemoRanges(values), isTrue,
              reason: '${w.id}/${e.id} = $values');
        }
      }
    });

    test('no duplicate start dates are ever written', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      await repo.seedMockData(today: _today);
      await _refresh();
      final starts = (await _weeks()).map((w) => DateTime(
          w.start.year, w.start.month, w.start.day));
      expect(starts.toSet().length, starts.length);
      expect(repo.duplicateWeeks, isEmpty);
      expect(collidingWeekStarts(repo.allWeeks), isEmpty);
    });
  });

  group('regenerating replaces the previous demo weeks', () {
    test('weeks outside the new plan are deleted', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      await _refresh();
      final before = (await _weeks()).where((w) => w.demo).map((w) => w.id).toSet();

      // A real week three months earlier moves the whole window back, so most
      // of the previous demo weeks fall outside the new plan.
      await db.collection('weeks').doc('real_jul').set({
        'name': 'Jul 6–12',
        'startDate': Timestamp.fromDate(DateTime(2026, 7, 6)),
        'createdAt': Timestamp.fromDate(DateTime(2026, 7, 6)),
      });
      await _refresh();
      await repo.seedMockData(today: _today);
      await _refresh();

      final after = (await _weeks()).where((w) => w.demo).map((w) => w.id).toSet();
      expect(after, isNot(before));
      expect(after.intersection(before).length, lessThan(before.length));
      // Nothing orphaned: no demo week survives outside the new plan.
      expect(await _demoEntryCount(), after.length * 7);
      expect(repo.duplicateWeeks, isEmpty);
    });

    test('entries of a removed employee are pruned from kept weeks', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      expect(await _demoEntryCount(), _expectedEntries);

      repo.employees = repo.employees.take(6).toList();
      await repo.seedMockData(today: _today);
      expect(await _demoEntryCount(), _expectedWeeks * 6);
    });
  });

  group('safety', () {
    test('the real week and its entries are never touched', () async {
      await _setUp();
      final before =
          (await db.collection('weeks').doc(_realWeekId).get()).data();
      await repo.seedMockData(today: _today);
      await repo.seedMockData(today: _today);
      await _refresh();

      final after =
          (await db.collection('weeks').doc(_realWeekId).get()).data();
      expect(after, before);
      expect(after!['mock'], isNull);
      final entry = await db
          .collection('weeks')
          .doc(_realWeekId)
          .collection('entries')
          .doc('e0')
          .get();
      expect(entry.data(), _realEntry);
      expect(await _entryCount(_realWeekId), 1);
    });

    test('demo weeks never land on a real week\'s start date', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      final starts = (await _weeks())
          .where((w) => w.demo)
          .map((w) => DateTime(w.start.year, w.start.month, w.start.day));
      expect(starts, isNot(contains(_realStart)));
    });

    test('clearing demo data leaves the real week alone', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      final removed = await repo.clearMockData();
      expect(removed, _expectedWeeks);
      final weeks = await _weeks();
      expect(weeks.map((w) => w.id), [_realWeekId]);
      expect(await _entryCount(_realWeekId), 1);
    });
  });

  group('refusals', () {
    test('refuses to run while legacy random-id demo weeks exist', () async {
      await _setUp();
      await db.collection('weeks').doc('3b7SRTFU2yTE6u29JA6e').set({
        'name': 'Sep 7–13',
        'startDate': Timestamp.fromDate(DateTime(2026, 9, 7)),
        'mock': true,
      });
      await _refresh();
      expect(repo.legacyDemoWeeks.map((w) => w.id), ['3b7SRTFU2yTE6u29JA6e']);

      await expectLater(
        repo.seedMockData(today: _today),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('cleanup'))),
      );
      // Nothing was written.
      expect((await _weeks()).length, 2);
      expect(repo.seeding.value, isFalse);
    });

    // The actual regression. The old generator was idempotent when run to
    // completion — it cleared, then added — so sequential runs looked fine.
    // Production ended up with 44 demo weeks because two runs overlapped:
    // both cleared, both then added a full set under random ids.
    test('two overlapping runs cannot duplicate anything', () async {
      await _setUp();
      final first = repo.seedMockData(today: _today);
      final second = repo.seedMockData(today: _today);

      final outcomes = await Future.wait([
        first.then((_) => 'ok').catchError((e) => 'threw: $e'),
        second.then((_) => 'ok').catchError((e) => 'threw: $e'),
      ]);
      // One run is turned away by the in-flight guard rather than racing.
      expect(outcomes.where((o) => o == 'ok'), hasLength(1));
      expect(outcomes.where((o) => o.startsWith('threw')), hasLength(1));

      await _refresh();
      expect((await _weeks()).where((w) => w.demo).length, _expectedWeeks);
      expect(await _demoEntryCount(), _expectedEntries);
      expect(repo.duplicateWeeks, isEmpty);
    });

    test('refuses a second concurrent run', () async {
      await _setUp();
      repo.seeding.value = true;
      await expectLater(
        repo.seedMockData(today: _today),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('already being generated'))),
      );
      repo.seeding.value = false;
    });

    test('refuses with no active employees, and clears the flag', () async {
      await _setUp();
      repo.employees = [];
      await expectLater(
          repo.seedMockData(today: _today), throwsA(isA<StateError>()));
      expect(repo.seeding.value, isFalse);
      expect((await _weeks()).length, 1); // just the real week
    });

    test('the in-flight flag is raised during a run and lowered after',
        () async {
      await _setUp();
      final seen = <bool>[];
      void listener() => seen.add(repo.seeding.value);
      repo.seeding.addListener(listener);
      await repo.seedMockData(today: _today);
      repo.seeding.removeListener(listener);
      expect(seen, [true, false]);
      expect(repo.seeding.value, isFalse);
    });
  });

  group('monthly totals from seeded data', () {
    test('equal the sum of the unique weeks only', () async {
      await _setUp();
      await repo.seedMockData(today: _today);
      await _refresh();
      repo.entriesByWeek = {};
      for (final w in repo.allWeeks) {
        final entries = await db
            .collection('weeks')
            .doc(w.id)
            .collection('entries')
            .get();
        repo.entriesByWeek[w.id] = entries.docs.map(Entry.fromDoc).toList();
      }

      final unique = dedupeWeeks(repo.allWeeks);
      expect(unique.length, _expectedWeeks + 1);
      for (final month in repo.monthlyTotals) {
        final inMonth = unique.where((w) =>
            w.startDate.year == month.month.year &&
            w.startDate.month == month.month.month);
        expect(inMonth.length, month.weekCount);
        for (final m in metrics) {
          expect(
            month.totals[m.key],
            inMonth.fold<int>(0, (t, w) => t + repo.totalsFor(w.id)[m.key]!),
            reason: '${m.label} in ${month.month}',
          );
        }
      }
    });
  });
}
