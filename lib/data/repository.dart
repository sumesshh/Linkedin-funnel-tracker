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

  late final _db = FirebaseFirestore.instance;
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

  /// Replaces any previous DEMO DATA with [months] of weekly demo entries
  /// for every active employee, placed before the earliest real week.
  /// Values come from [demoValues] (deterministic, within [demoRanges] per
  /// employee per week). Demo weeks are tagged `mock: true`; real weeks and
  /// their entries are never written to.
  Future<int> seedMockData({int months = 5}) async {
    final emps = activeEmployees;
    if (emps.isEmpty) {
      throw StateError('Add at least one active employee first.');
    }
    await clearMockData();
    final plan = planDemoWeeks(
      weeks.where((w) => !w.isDemo).map((w) => w.startDate),
      DateTime.now(),
      months: months,
    );

    final ops = <void Function(WriteBatch)>[];
    for (final (:start, :name, :progress) in plan) {
      final weekRef = _weeksRef.doc();
      ops.add((b) => b.set(weekRef, {
            'name': name,
            'startDate': Timestamp.fromDate(start),
            'createdAt': FieldValue.serverTimestamp(),
            'mock': true,
          }));
      for (final emp in emps) {
        final v = demoValues(emp.name, start, progress: progress);
        ops.add((b) => b.set(weekRef.collection('entries').doc(emp.id), {
              'employeeName': emp.name,
              for (final m in metrics) m.key: v[m.key] ?? 0,
              'updatedAt': FieldValue.serverTimestamp(),
            }));
      }
    }
    await _commitInChunks(ops);
    return plan.length;
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

  /// Firestore batches are capped at 500 writes.
  Future<void> _commitInChunks(List<void Function(WriteBatch)> ops) async {
    for (var i = 0; i < ops.length; i += 450) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(450)) {
        op(batch);
      }
      await batch.commit();
    }
  }
}
