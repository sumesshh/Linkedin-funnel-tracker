import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/widgets/breakdown_table.dart';

// Production-shaped data: the 7 names and the Oct 12–15 numbers.
final _entries = [
  for (final (i, n) in [
    'sumesh',
    'smrithi',
    'rajeev',
    'teena',
    'abhinav',
    'johny',
    'prince thomas',
  ].indexed)
    Entry(
      weekId: 'w',
      employeeId: 'e$i',
      employeeName: n,
      values: {
        'posts': [2, 44, 7, 88, 7, 5, 80][i],
        'comments': [4, 7, 77, 78, 58, 7, 77][i],
        'likes': [55, 880, 666, 242, 555, 788, 44][i],
        'reach': [788, 888, 987, 457, 666, 88, 4][i],
        'profileViews': [189, 139, 300, 79, 172, 139, 172][i],
        'inboundDMs': [8, 3, 2, 2, 15, 3, 2][i],
        'academyEnquiries': [5, 2, 3, 1, 4, 1, 3][i],
        'studiosEnquiries': [1, 4, 8, 1, 3, 2, 2][i],
      },
    ),
];

void main() {
  testWidgets('diag', (tester) async {
    late BreakdownLayout layout;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            layout = measureBreakdown(context, _entries, sumEntries(_entries));
            return const SizedBox();
          },
        ),
      ),
    );
    debugPrint('name=${layout.nameWidth} metrics=${layout.metricWidths} '
        'full=${layout.fullWidth} min=${layout.minWidth} '
        'row=${layout.rowHeight}');
    for (final (w, avail) in [
      (375.0, 375.0 - 72),
      (623.0, 623.0 - 177),
      (800.0, 800.0 - 177),
      (1024.0, 1024.0 - 177),
      (1280.0, 1100.0 - 40),
    ]) {
      final mode = avail < layout.minWidth
          ? 'CARDS'
          : (layout.fullWidth <= avail
                ? 'table, fits'
                : 'table, scrolls (${(layout.fullWidth - avail).round()}px out '
                      'of view)');
      debugPrint('viewport ${w.round()} -> avail ${avail.round()}: $mode');
    }
  });
}
