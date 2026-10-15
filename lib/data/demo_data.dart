import 'dart:math' as math;

/// DEMO DATA limits for ONE employee in ONE week (inclusive). Combined weekly
/// totals across employees are not limited.
const demoRanges = <String, (int, int)>{
  'posts': (0, 5),
  'comments': (0, 30),
  'likes': (0, 150),
  'reach': (100, 950),
  'profileViews': (0, 300),
  'inboundDMs': (0, 15),
  'academyEnquiries': (0, 10),
  'studiosEnquiries': (0, 10),
};

/// Employees whose account is used only for reposts, so they never author
/// posts (compared case-insensitively).
const repostOnlyEmployees = {'prince thomas'};

bool isRepostOnly(String employeeName) =>
    repostOnlyEmployees.contains(employeeName.trim().toLowerCase());

/// Count-like metrics that are usually small; skewed towards the low end.
const _rare = {'inboundDMs', 'academyEnquiries', 'studiosEnquiries'};

/// Stable string hash (the same on the VM and the web, unlike `hashCode`).
int _hash(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) % 2147483647;
  }
  return h;
}

/// Deterministic DEMO DATA for one employee in the week starting
/// [weekStart]: the same inputs always give the same numbers, and every value
/// stays inside [demoRanges]. [progress] (0 = oldest week, 1 = newest) adds a
/// gentle upward trend.
Map<String, int> demoValues(
  String employeeName,
  DateTime weekStart, {
  double progress = 0.5,
}) {
  final name = employeeName.trim().toLowerCase();
  // Each employee has a consistent activity level, so people differ.
  final activity = 0.35 + 0.55 * math.Random(_hash(name)).nextDouble();
  final rnd = math.Random(_hash(
      '$name|${weekStart.year}-${weekStart.month}-${weekStart.day}'));
  final trend = 0.85 + 0.3 * progress.clamp(0, 1);

  return {
    for (final MapEntry(key: k, value: (lo, hi)) in demoRanges.entries)
      k: () {
        if (k == 'posts' && isRepostOnly(employeeName)) return 0;
        var level =
            (activity * trend * (0.4 + 1.2 * rnd.nextDouble())).clamp(0.0, 1.0);
        if (_rare.contains(k)) level *= level;
        return (lo + ((hi - lo) * level).round()).clamp(lo, hi);
      }(),
  };
}

/// One planned DEMO DATA week.
typedef DemoWeek = ({DateTime start, String name, double progress});

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The Monday-starting demo weeks covering the [months] before the earliest
/// of [realWeekStarts] (or before [today] when there are none), skipping any
/// date a real week already uses. Oldest first.
List<DemoWeek> planDemoWeeks(
  Iterable<DateTime> realWeekStarts,
  DateTime today, {
  int months = 5,
}) {
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  final real = realWeekStarts.map(dateOnly).toList()..sort();
  var end = real.isEmpty ? dateOnly(today) : real.first;
  end = DateTime(end.year, end.month, end.day - (end.weekday - 1)); // Monday
  final first = DateTime(end.year, end.month - months, end.day);
  var start =
      DateTime(first.year, first.month, first.day - (first.weekday - 1));

  final taken = real.toSet();
  final starts = <DateTime>[];
  while (start.isBefore(end)) {
    if (!taken.contains(start)) starts.add(start);
    start = DateTime(start.year, start.month, start.day + 7);
  }
  return [
    for (final (i, s) in starts.indexed)
      (
        start: s,
        name: () {
          final e = s.add(const Duration(days: 6));
          return s.month == e.month
              ? '${_mon[s.month - 1]} ${s.day}–${e.day}'
              : '${_mon[s.month - 1]} ${s.day}–${_mon[e.month - 1]} ${e.day}';
        }(),
        progress: i / math.max(starts.length - 1, 1),
      ),
  ];
}

/// True when every metric in [values] is inside [demoRanges]. Demo weeks
/// that fail this were made by an older generator and should be regenerated.
bool withinDemoRanges(Map<String, int> values) => demoRanges.entries.every(
    (r) => (values[r.key] ?? 0) >= r.value.$1 && (values[r.key] ?? 0) <= r.value.$2);
