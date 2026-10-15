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
