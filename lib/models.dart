import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// One of the 8 tracked LinkedIn metrics.
class Metric {
  final String key; // Firestore field name
  final String label; // full label
  final String short; // table column label
  final Color color;

  const Metric(this.key, this.label, this.short, this.color);
}

const metrics = <Metric>[
  Metric('posts', 'Posts', 'Posts', Color(0xFF4285F4)),
  Metric('comments', 'Comments', 'Comments', Color(0xFFEA4335)),
  Metric('likes', 'Likes', 'Likes', Color(0xFFFBBC04)),
  Metric('reach', 'Reach / Impressions', 'Reach', Color(0xFF34A853)),
  Metric('profileViews', 'Profile Views', 'Profile Views', Color(0xFFFF6D00)),
  Metric('inboundDMs', 'Inbound DMs', 'DMs', Color(0xFF45BCC0)),
  Metric('academyEnquiries', 'Academy enquiries', 'Academy', Color(0xFF7B1FA2)),
  Metric('studiosEnquiries', 'Studios enquiries', 'Studios', Color(0xFF795548)),
];

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

class Employee {
  final String id;
  final String name;
  final int order;
  final bool isActive;
  final DateTime? createdAt;

  const Employee({
    required this.id,
    required this.name,
    required this.order,
    required this.isActive,
    this.createdAt,
  });

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Employee(
      id: d.id,
      name: (m['name'] ?? '') as String,
      order: _int(m['order']),
      isActive: (m['isActive'] ?? true) as bool,
      createdAt: _date(m['createdAt']),
    );
  }
}

class Week {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime? createdAt;

  /// Generated DEMO DATA (stored with `mock: true`), never real analytics.
  final bool isDemo;

  const Week({
    required this.id,
    required this.name,
    required this.startDate,
    this.createdAt,
    this.isDemo = false,
  });

  factory Week.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final created = _date(m['createdAt']);
    return Week(
      id: d.id,
      name: (m['name'] ?? '') as String,
      startDate: _date(m['startDate']) ?? created ?? DateTime(2000),
      createdAt: created,
      isDemo: m['mock'] == true,
    );
  }
}

/// One employee's numbers for one week (weeks/{weekId}/entries/{employeeId}).
class Entry {
  final String weekId;
  final String employeeId;
  final String employeeName;
  final Map<String, int> values;

  const Entry({
    required this.weekId,
    required this.employeeId,
    required this.employeeName,
    required this.values,
  });

  int operator [](String key) => values[key] ?? 0;

  factory Entry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Entry(
      weekId: d.reference.parent.parent!.id,
      employeeId: d.id,
      employeeName: (m['employeeName'] ?? '') as String,
      values: {for (final mt in metrics) mt.key: _int(m[mt.key])},
    );
  }
}

/// Sums each metric across [entries].
Map<String, int> sumEntries(Iterable<Entry> entries) {
  final totals = {for (final m in metrics) m.key: 0};
  for (final e in entries) {
    for (final m in metrics) {
      totals[m.key] = totals[m.key]! + e[m.key];
    }
  }
  return totals;
}

/// Orders a week's entries by the employees' display order; entries for
/// deleted employees go last, alphabetically.
List<Entry> sortEntries(List<Entry> entries, List<Employee> employees) {
  final order = {for (final e in employees) e.id: e.order};
  return [...entries]..sort((a, b) {
      final oa = order[a.employeeId], ob = order[b.employeeId];
      if (oa != null && ob != null) return oa.compareTo(ob);
      if (oa != null) return -1;
      if (ob != null) return 1;
      return a.employeeName.compareTo(b.employeeName);
    });
}

/// The local calendar day a week starts on. This — not the document id — is a
/// week's identity: two documents sharing a start date are the same week.
///
/// Built in local time on purpose. Start dates are stored as local midnight
/// (IST midnight serialises as 18:30Z the day before), so reading the UTC
/// parts would put a week in the wrong day, and sometimes the wrong month.
DateTime weekStartKey(Week w) =>
    DateTime(w.startDate.year, w.startDate.month, w.startDate.day);

/// Whether demo week [a] should be kept over demo week [b] when both start
/// on the same day: the oldest document wins, so a re-run that duplicated a
/// week loses to the original. Ties break on id, so the winner never depends
/// on the order Firestore returns documents in.
bool _preferDemoWeek(Week a, Week b) {
  final ca = a.createdAt, cb = b.createdAt;
  if ((ca == null) != (cb == null)) return ca != null;
  if (ca != null && cb != null && ca != cb) return ca.isBefore(cb);
  return a.id.compareTo(b.id) < 0;
}

/// Orders weeks oldest first, breaking ties on id so the order is stable.
int _byStartThenId(Week a, Week b) {
  final c = a.startDate.compareTo(b.startDate);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// One demo week per start date, oldest first.
///
/// Duplicate demo documents — e.g. from a seed that ran twice — would
/// otherwise be summed once each, inflating every monthly total while the
/// weekly view (one bar per document) still looked correct.
///
/// Real weeks are never collapsed or hidden, even if two of them share a
/// start date: real analytics are never silently dropped, so a genuine
/// collision stays visible for someone to resolve. [hiddenDuplicates] and
/// [collidingWeekStarts] report what needs attention.
List<Week> dedupeWeeks(Iterable<Week> weeks) {
  final kept = <Week>[];
  final demo = <DateTime, Week>{};
  for (final w in weeks) {
    if (!w.isDemo) {
      kept.add(w);
      continue;
    }
    final key = weekStartKey(w);
    final cur = demo[key];
    if (cur == null || _preferDemoWeek(w, cur)) demo[key] = w;
  }
  return [...kept, ...demo.values]..sort(_byStartThenId);
}

/// The duplicate demo documents [dedupeWeeks] leaves out, oldest first.
List<Week> hiddenDuplicates(Iterable<Week> weeks) {
  final shown = {for (final w in dedupeWeeks(weeks)) w.id};
  return [for (final w in weeks) if (!shown.contains(w.id)) w]
    ..sort(_byStartThenId);
}

/// Start dates carrying more than one *visible* week, i.e. two real weeks, or
/// a real week a demo week landed on. Nothing hides these, so they would be
/// counted twice in a monthly total; the UI surfaces them instead.
List<DateTime> collidingWeekStarts(Iterable<Week> weeks) {
  final byStart = <DateTime, int>{};
  for (final w in dedupeWeeks(weeks)) {
    byStart.update(weekStartKey(w), (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final MapEntry(key: start, value: n) in byStart.entries)
      if (n > 1) start,
  ]..sort();
}
