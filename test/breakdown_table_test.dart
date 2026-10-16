import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/widgets/breakdown_table.dart';
import 'package:linkedin_dashboard/widgets/common.dart';

const _names = ['Asha Menon', 'Rahul Nair', 'Prince Thomas'];

/// Distinct per employee and metric, so a finder cannot match the wrong cell.
final _entries = [
  for (final (i, name) in _names.indexed)
    Entry(
      weekId: 'w1',
      employeeId: 'e$i',
      employeeName: name,
      // A disjoint range per metric, so no cell shares its text with
      // another cell or with a column total.
      values: {
        for (final (j, m) in metrics.indexed) m.key: (j + 1) * 1000 + i,
      },
    ),
];
final _totals = sumEntries(_entries);

/// Pumps the table into exactly [width] logical pixels, laid out from the
/// top-left corner so global coordinates are the table's own.
Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: BreakdownTable(entries: _entries, totals: _totals),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the metric columns to their far left/right end.
Future<void> _scroll(WidgetTester tester, double dx) async {
  await tester.drag(find.byType(SingleChildScrollView), Offset(dx, 0));
  await tester.pumpAndSettle();
}

bool _withinViewport(WidgetTester tester, Finder f, double width) {
  final r = tester.getRect(f);
  return r.left >= -0.5 && r.right <= width + 0.5;
}

void main() {
  testWidgets('at 623px the scrollbar shows and Studios scrolls into view', (
    tester,
  ) async {
    const width = 623.0;
    await _pumpAt(tester, width);

    // The table, not the card layout.
    expect(find.text('Employee Name'), findsOneWidget);

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);

    // Studios starts out past the right edge, and the right-hand fade says so.
    expect(_withinViewport(tester, find.text('Studios'), width), isFalse);
    expect(find.byKey(BreakdownScrollFades.rightKey), findsOneWidget);
    expect(find.byKey(BreakdownScrollFades.leftKey), findsNothing);

    final nameBefore = tester.getRect(find.text('Asha Menon'));
    await _scroll(tester, -600);

    expect(_withinViewport(tester, find.text('Studios'), width), isTrue);
    expect(_withinViewport(tester, find.text('Academy'), width), isTrue);
    // The name column is pinned: it did not move with the metrics.
    expect(tester.getRect(find.text('Asha Menon')), nameBefore);
    // Scrolled to the end: the hint flips to the left edge.
    expect(find.byKey(BreakdownScrollFades.leftKey), findsOneWidget);
    expect(find.byKey(BreakdownScrollFades.rightKey), findsNothing);
  });

  testWidgets('the Total row shows Posts…Reach without scrolling at 623px', (
    tester,
  ) async {
    const width = 623.0;
    await _pumpAt(tester, width);

    expect(_withinViewport(tester, find.text('Total'), width), isTrue);
    for (final key in ['posts', 'comments', 'likes', 'reach']) {
      final m = metrics.firstWhere((m) => m.key == key);
      expect(
        _withinViewport(tester, find.text(m.short), width),
        isTrue,
        reason: '${m.short} header is off-screen',
      );
      expect(
        _withinViewport(tester, find.text(fmt(_totals[key]!)), width),
        isTrue,
        reason: '${m.short} total is off-screen',
      );
    }
  });

  testWidgets('a wide table fits with no scrollbar and no fades', (
    tester,
  ) async {
    const width = 1280.0;
    await _pumpAt(tester, width);

    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byKey(BreakdownScrollFades.rightKey), findsNothing);
    expect(find.byKey(BreakdownScrollFades.leftKey), findsNothing);
    for (final m in metrics) {
      expect(
        _withinViewport(tester, find.text(m.short), width),
        isTrue,
        reason: '${m.short} is off-screen at ${width}px',
      );
    }
  });

  testWidgets('too narrow for Posts…Reach falls back to cards', (
    tester,
  ) async {
    await _pumpAt(tester, 375);

    expect(find.text('Employee Name'), findsNothing); // no table header
    expect(find.byType(Scrollbar), findsNothing);
    // One card per employee plus the Total card, each listing every metric.
    expect(find.text('Studios'), findsNWidgets(_entries.length + 1));
    expect(find.text('Total'), findsOneWidget);
  });

  for (final width in [375.0, 623.0, 800.0, 1024.0, 1280.0]) {
    testWidgets('Academy and Studios are reachable at ${width}px', (
      tester,
    ) async {
      await _pumpAt(tester, width);

      if (find.text('Employee Name').evaluate().isEmpty) {
        // Card layout: every metric is listed in full on each card.
        expect(find.text('Academy'), findsNWidgets(_entries.length + 1));
        expect(find.text('Studios'), findsNWidgets(_entries.length + 1));
        return;
      }
      if (!_withinViewport(tester, find.text('Studios'), width)) {
        // Overflowing: the scrollbar is visible and brings the rest in.
        expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
            isTrue);
        expect(find.byKey(BreakdownScrollFades.rightKey), findsOneWidget);
        await _scroll(tester, -800);
      }
      expect(_withinViewport(tester, find.text('Academy'), width), isTrue);
      expect(_withinViewport(tester, find.text('Studios'), width), isTrue);
    });
  }
}
