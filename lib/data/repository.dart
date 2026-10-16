import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../widgets/metric_chart.dart' show axisScale, ChartPeriod;
import 'demo_data.dart';

/// Single source of truth. Listens to Firestore once at startup (3 live
/// queries) and exposes the latest snapshot to every screen, so navigating
/// around the app costs no extra reads.
class Repository extends ChangeNotifier {
  Repository._();
  static final instance = Repository._();

  late FirebaseFirestore _db = FirebaseFirestore.instance;

  /// True while [seedMockData] is running. Both Generate buttons watch this
  /// and disable themselves: two overlapping runs are what created 22
  /// duplicate demo weeks in the first place.
  final seeding = ValueNotifier<bool>(false);

  /// Points the repository at a fake Firestore and clears cached state.
  @visibleForTesting
  void useFirestoreForTests(FirebaseFirestore db) {
    _db = db;
    employees = [];
    weeks = [];
    allWeeks = [];
    entriesByWeek = {};
    error = null;
    seeding.value = false;
  }
  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _db.collection('employees');
  CollectionReference<Map<String, dynamic>> get _weeksRef =>
      _db.collection('weeks');
  CollectionReference<Map<String, dynamic>> _entriesRef(String weekId) =>
      _weeksRef.doc(weekId).collection('entries');

  List<Employee> employees = [];

  /// Chronological, one week per start date — what every screen, export and
  /// report reads. Duplicate documents for the same week are collapsed by
  /// [dedupeWeeks]; [allWeeks] still holds them for cleanup and diagnostics.
  List<Week> weeks = [];

  /// Every week document exactly as stored, duplicates included.
  List<Week> allWeeks = [];
  Map<String, List<Entry>> entriesByWeek = {};
  Object? error;

  bool _employeesLoaded = false, _weeksLoaded = false, _entriesLoaded = false;
  bool get loaded => _employeesLoaded && _weeksLoaded && _entriesLoaded;

  final _subs = <StreamSubscription>[];

  void start() {
    if (_subs.isNotEmpty) return;
    _subs.add(_employeesRef.orderBy('order').snapshots().listen((s) {
      employees = s.docs.map(Employee.fromDoc).toList();
      _employeesLoaded = true;
      notifyListeners();
    }, onError: _onError));
    _subs.add(_weeksRef.orderBy('startDate').snapshots().listen((s) {
      allWeeks = s.docs.map(Week.fromDoc).toList();
      weeks = dedupeWeeks(allWeeks);
      _weeksLoaded = true;
      notifyListeners();
    }, onError: _onError));
    _subs.add(_db.collectionGroup('entries').snapshots().listen((s) {
      final map = <String, List<Entry>>{};
      for (final d in s.docs) {
        final e = Entry.fromDoc(d);
        (map[e.weekId] ??= []).add(e);
      }
      entriesByWeek = map;
      _entriesLoaded = true;
      notifyListeners();
    }, onError: _onError));
  }

  void _onError(Object e) {
    error = e;
    notifyListeners();
  }

  List<Employee> get activeEmployees =>
      employees.where((e) => e.isActive).toList();

  /// A week's entries in employee display order, labelled with each
  /// employee's current name (the copy stored on the entry can be stale, e.g.
  /// after a rename in the Firebase console). Deleted employees keep the
  /// stored name.
  List<Entry> entriesFor(String weekId) {
    final names = {for (final e in employees) e.id: e.name};
    return sortEntries([
      for (final e in entriesByWeek[weekId] ?? const <Entry>[])
        Entry(
          weekId: e.weekId,
          employeeId: e.employeeId,
          employeeName: names[e.employeeId] ?? e.employeeName,
          values: e.values,
        ),
    ], employees);
  }

  Map<String, int> totalsFor(String weekId) =>
      sumEntries(entriesByWeek[weekId] ?? const []);

  /// All-employee totals per calendar month (a week counts toward the month
  /// its start date falls in), oldest first.
  ///
  /// Deduped again here rather than trusting [weeks]: a month that counted one
  /// week twice would disagree with the weekly view, which is how the October
  /// Reach total reached 13,900 against an actual 8,896.
  List<({DateTime month, int weekCount, Map<String, int> totals})>
      get monthlyTotals {
    final byMonth = <DateTime, List<Week>>{};
    for (final w in dedupeWeeks(weeks)) {
      (byMonth[DateTime(w.startDate.year, w.startDate.month)] ??= []).add(w);
    }
    final months = byMonth.keys.toList()..sort();
    return [
      for (final m in months)
        (
          month: m,
          weekCount: byMonth[m]!.length,
          totals: sumEntries(
              byMonth[m]!.expand((w) => entriesByWeek[w.id] ?? const [])),
        ),
    ];
  }

  // ---------------------------------------------------------------- weeks

  Future<String> createWeek(String name, DateTime startDate) async {
    final doc = await _weeksRef.add({
      'name': name.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateWeek(String id, String name, DateTime startDate) =>
      _weeksRef.doc(id).update({
        'name': name.trim(),
        'startDate': Timestamp.fromDate(startDate),
      });

  Future<void> deleteWeek(String id) async {
    final entries = await _entriesRef(id).get();
    await _commitInChunks([
      for (final d in entries.docs) (WriteBatch b) => b.delete(d.reference),
      (WriteBatch b) => b.delete(_weeksRef.doc(id)),
    ]);
  }

  /// Writes every employee's numbers for [weekId] in one go.
  Future<void> saveEntries(
    String weekId,
    Map<Employee, Map<String, int>> values,
  ) =>
      _commitInChunks([
        for (final MapEntry(key: emp, value: v) in values.entries)
          (WriteBatch b) => b.set(_entriesRef(weekId).doc(emp.id), {
                'employeeName': emp.name,
                for (final m in metrics) m.key: v[m.key] ?? 0,
                'updatedAt': FieldValue.serverTimestamp(),
              }),
      ]);

  /// Writes the edited numbers for one week's existing rows, keyed by
  /// employee id.
  ///
  /// Unlike [saveEntries] this takes the rows as they are stored rather than
  /// a list of [Employee]s, so a row whose employee has since been deleted —
  /// the history stays in the week — is still editable. Merged, so any field
  /// this app does not know about survives the write.
  Future<void> saveEntryValues(String weekId, Iterable<Entry> entries) =>
      _commitInChunks([
        for (final e in entries)
          (WriteBatch b) => b.set(
                _entriesRef(weekId).doc(e.employeeId),
                {
                  'employeeName': e.employeeName,
                  for (final m in metrics) m.key: e[m.key],
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              ),
      ]);

  // ------------------------------------------------------------ employees

  Future<void> addEmployee(String name) {
    final nextOrder = employees.isEmpty
        ? 1
        : employees.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1;
    return _employeesRef.add({
      'name': name.trim(),
      'order': nextOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });
  }

  /// Renames the employee and the name copied into their existing entries.
  Future<void> renameEmployee(String id, String name) async {
    final trimmed = name.trim();
    final ops = <void Function(WriteBatch)>[
      (b) => b.update(_employeesRef.doc(id), {'name': trimmed}),
    ];
    for (final list in entriesByWeek.values) {
      for (final e in list.where((e) => e.employeeId == id)) {
        ops.add((b) => b.update(_entriesRef(e.weekId).doc(id),
            {'employeeName': trimmed}));
      }
    }
    await _commitInChunks(ops);
  }

  Future<void> setEmployeeActive(String id, bool active) =>
      _employeesRef.doc(id).update({'isActive': active});

  /// Removes the employee only; their historical entries stay in each week.
  Future<void> deleteEmployee(String id) => _employeesRef.doc(id).delete();

  Future<void> reorderEmployees(List<Employee> ordered) {
    // Optimistic local update so the list doesn't jump while saving.
    employees = [
      for (var i = 0; i < ordered.length; i++)
        Employee(
          id: ordered[i].id,
          name: ordered[i].name,
          order: i + 1,
          isActive: ordered[i].isActive,
          createdAt: ordered[i].createdAt,
        ),
    ];
    notifyListeners();
    return _commitInChunks([
      for (var i = 0; i < ordered.length; i++)
        (WriteBatch b) =>
            b.update(_employeesRef.doc(ordered[i].id), {'order': i + 1}),
    ]);
  }

  // ---------------------------------------------------------- sample data

  /// Demo documents are keyed by the week they cover, so regenerating
  /// overwrites the previous run instead of adding a second copy of it.
  static const demoIdPrefix = 'demo_';

  /// `demo_2026-10-05` for the week starting 5 Oct 2026. Built from the local
  /// date parts, matching [weekStartKey].
  static String demoWeekId(DateTime start) => '$demoIdPrefix'
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  /// Demo weeks written by the old generator, which used random document ids.
  /// These are the ones that can duplicate, so the seed refuses to run until
  /// the cleanup has removed them.
  List<Week> get legacyDemoWeeks => [
        for (final w in allWeeks)
          if (w.isDemo && !w.id.startsWith(demoIdPrefix)) w,
      ];

  /// Duplicate demo documents the UI is hiding (see [hiddenDuplicates]).
  List<Week> get duplicateWeeks => hiddenDuplicates(allWeeks);

  /// Regenerates the DEMO DATA: [months] of weekly demo entries for every
  /// active employee, placed before the earliest real week.
  ///
  /// Idempotent. Every document is keyed by what it represents
  /// ([demoWeekId] per week, the employee id per entry) and written with
  /// `set(..., merge: true)`, so running this twice overwrites the first run
  /// instead of adding a second copy of it. Weeks left over from a previous
  /// run — dates no longer in the plan — are then deleted, which is what
  /// makes "generating again replaces the previous demo weeks" true.
  ///
  /// Refuses to run while [legacyDemoWeeks] exist: those carry random ids
  /// that this method cannot overwrite, so seeding on top of them would
  /// duplicate them again. Run the cleanup first.
  ///
  /// Only documents tagged `mock: true` are ever created, modified or
  /// deleted. Real weeks and their entries are never written to.
  Future<int> seedMockData({int months = 5, DateTime? today}) async {
    if (seeding.value) {
      throw StateError('Demo data is already being generated.');
    }
    final emps = activeEmployees;
    if (emps.isEmpty) {
      throw StateError('Add at least one active employee first.');
    }
    final legacy = legacyDemoWeeks;
    if (legacy.isNotEmpty) {
      throw StateError(
        '${legacy.length} demo weeks from an older version still have random '
        'document ids and cannot be replaced safely. Run the duplicate '
        'cleanup (tools/dedupe_demo_weeks.mjs) first, then generate again.',
      );
    }

    seeding.value = true;
    try {
      final plan = planDemoWeeks(
        allWeeks.where((w) => !w.isDemo).map((w) => w.startDate),
        today ?? DateTime.now(),
        months: months,
      );

      final ops = <void Function(WriteBatch)>[];
      final planned = <String>{};
      for (final (:start, :name, :progress) in plan) {
        final weekRef = _weeksRef.doc(demoWeekId(start));
        planned.add(weekRef.id);
        ops.add((b) => b.set(
              weekRef,
              {
                'name': name,
                'startDate': Timestamp.fromDate(start),
                'createdAt': FieldValue.serverTimestamp(),
                'mock': true,
              },
              SetOptions(merge: true),
            ));
        for (final emp in emps) {
          final v = demoValues(emp.name, start, progress: progress);
          ops.add((b) => b.set(
                weekRef.collection('entries').doc(emp.id),
                {
                  'employeeName': emp.name,
                  for (final m in metrics) m.key: v[m.key] ?? 0,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              ));
        }
      }
      await _commitInChunks(ops);
      await _pruneDemoData(planned, {for (final e in emps) e.id});
      return plan.length;
    } finally {
      seeding.value = false;
    }
  }

  /// Deletes demo weeks outside [plannedWeekIds], and entries inside the
  /// planned weeks belonging to employees no longer in [plannedEmployeeIds]
  /// (someone removed or deactivated since the last run).
  ///
  /// Reads the weeks collection rather than the cached list so a stale
  /// snapshot cannot leave a duplicate behind. Documents without
  /// `mock: true` are filtered out and never touched.
  Future<void> _pruneDemoData(
    Set<String> plannedWeekIds,
    Set<String> plannedEmployeeIds,
  ) async {
    final demo = await _weeksRef.where('mock', isEqualTo: true).get();
    for (final doc in demo.docs) {
      if (doc.data()['mock'] != true) continue; // defensive
      if (!plannedWeekIds.contains(doc.id)) {
        await deleteWeek(doc.id);
        continue;
      }
      final entries = await _entriesRef(doc.id).get();
      final stale = [
        for (final e in entries.docs)
          if (!plannedEmployeeIds.contains(e.id)) e.reference,
      ];
      if (stale.isNotEmpty) {
        await _commitInChunks([
          for (final ref in stale) (WriteBatch b) => b.delete(ref),
        ]);
      }
    }
  }

  /// Demo weeks holding values outside [demoRanges], i.e. left over from an
  /// older generator (e.g. 4,000+ reach per employee).
  List<Week> get staleDemoWeeks => [
        for (final w in weeks)
          if (w.isDemo &&
              (entriesByWeek[w.id] ?? const <Entry>[])
                  .any((e) => !withinDemoRanges(e.values)))
            w,
      ];

  /// TEMPORARY diagnostics: per week, the employee record count, each
  /// employee's reach, the combined reach and the weekly Y-axis maximum.
  String diagnostics() {
    final b = StringBuffer();
    for (final w in weeks) {
      final es = entriesFor(w.id);
      final total = sumEntries(es)['reach']!;
      final maxAll = sumEntries(es).values.fold<int>(0, math.max);
      b.writeln('[${w.isDemo ? 'DEMO' : 'REAL'}] ${w.name}: ${es.length} records, '
          'reach ${es.map((e) => '${e.employeeName}=${e['reach']}').join(', ')} '
          '| combined reach=$total | max any metric=$maxAll '
          '| yMax=${axisScale(maxAll, ChartPeriod.weekly).maxY.toInt()}');
    }
    return b.toString();
  }

  /// Deletes every week created by [seedMockData], with its entries.
  Future<int> clearMockData() async {
    final mock = await _weeksRef.where('mock', isEqualTo: true).get();
    for (final w in mock.docs) {
      await deleteWeek(w.id);
    }
    return mock.docs.length;
  }

  // --------------------------------------------------------------- backup

  /// Whole database as plain JSON-encodable data.
  Map<String, dynamic> exportData() => {
        'app': 'LinkedIn Analytics Dashboard',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'employees': [
          for (final e in employees)
            {
              'id': e.id,
              'name': e.name,
              'order': e.order,
              'isActive': e.isActive,
              'createdAt': e.createdAt?.toIso8601String(),
            },
        ],
        'weeks': [
          for (final w in weeks)
            {
              'id': w.id,
              'name': w.name,
              'startDate': w.startDate.toIso8601String(),
              'createdAt': w.createdAt?.toIso8601String(),
              if (w.isDemo) 'mock': true,
              'entries': [
                for (final e in entriesFor(w.id))
                  {
                    'employeeId': e.employeeId,
                    'employeeName': e.employeeName,
                    ...e.values,
                  },
              ],
            },
        ],
      };

  /// Restores an export. Documents are written by id, so importing on top of
  /// existing data overwrites matching records and keeps everything else.
  Future<({int employees, int weeks, int entries})> importData(
      Map<String, dynamic> data) async {
    Timestamp? ts(Object? v) {
      final d = v is String ? DateTime.tryParse(v) : null;
      return d == null ? null : Timestamp.fromDate(d);
    }

    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    final emps = (data['employees'] as List? ?? const []).cast<Map>();
    final wks = (data['weeks'] as List? ?? const []).cast<Map>();
    if (emps.isEmpty && wks.isEmpty) {
      throw const FormatException('No employees or weeks found in this file.');
    }

    final ops = <void Function(WriteBatch)>[];
    for (final e in emps) {
      ops.add((b) => b.set(_employeesRef.doc('${e['id']}'), {
            'name': '${e['name'] ?? ''}',
            'order': n(e['order']),
            'isActive': e['isActive'] != false,
            'createdAt': ts(e['createdAt']) ?? FieldValue.serverTimestamp(),
          }));
    }
    var entryCount = 0;
    for (final w in wks) {
      final weekId = '${w['id']}';
      ops.add((b) => b.set(_weeksRef.doc(weekId), {
            'name': '${w['name'] ?? ''}',
            'startDate': ts(w['startDate']) ?? Timestamp.now(),
            'createdAt': ts(w['createdAt']) ?? FieldValue.serverTimestamp(),
            if (w['mock'] == true) 'mock': true,
          }));
      for (final e in (w['entries'] as List? ?? const []).cast<Map>()) {
        entryCount++;
        ops.add((b) => b.set(_entriesRef(weekId).doc('${e['employeeId']}'), {
              'employeeName': '${e['employeeName'] ?? ''}',
              for (final m in metrics) m.key: n(e[m.key]),
              'updatedAt': FieldValue.serverTimestamp(),
            }));
      }
    }
    await _commitInChunks(ops);
    return (employees: emps.length, weeks: wks.length, entries: entryCount);
  }

  /// Firestore batches are capped at 500 writes; 400 leaves headroom.
  Future<void> _commitInChunks(List<void Function(WriteBatch)> ops) async {
    for (var i = 0; i < ops.length; i += 400) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(400)) {
        op(batch);
      }
      await batch.commit();
    }
  }
}
