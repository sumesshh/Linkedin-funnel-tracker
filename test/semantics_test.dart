import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/screens/data_entry_screen.dart';
import 'package:linkedin_dashboard/screens/manage_employees_screen.dart';
import 'package:linkedin_dashboard/screens/manage_weeks_screen.dart';
import 'package:linkedin_dashboard/widgets/metric_chart.dart';

const _employees = [
  Employee(id: 'e0', name: 'Asha Menon', order: 1, isActive: true),
  Employee(id: 'e1', name: 'Rahul Nair', order: 2, isActive: false),
];

Week _week(String id, String name, DateTime start) =>
    Week(id: id, name: name, startDate: start, createdAt: start);

List<Entry> _entries(String weekId) => [
  for (final e in _employees)
    Entry(
      weekId: weekId,
      employeeId: e.id,
      employeeName: e.name,
      values: {for (final m in metrics) m.key: 12},
    ),
];

/// Fills [Repository.instance] in place, the way the other tests do, so the
/// screens can be pumped without Firestore.
void _seed() {
  final repo = Repository.instance;
  repo.employees = _employees;
  repo.allWeeks = [
    _week('w1', 'Sep 29-Oct 5', DateTime(2026, 9, 29)),
    _week('w2', 'Oct 6-12', DateTime(2026, 10, 6)),
  ];
  repo.weeks = repo.allWeeks;
  repo.entriesByWeek = {for (final w in repo.weeks) w.id: _entries(w.id)};
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

/// What a screen reader would announce for [node]. Flutter web folds
/// [SemanticsData.tooltip] into the DOM label, so a control named only by a
/// tooltip still reaches the browser with an accessible name.
String _name(SemanticsNode node) {
  final data = node.getSemanticsData();
  return [data.label, data.tooltip].where((s) => s.isNotEmpty).join(' ').trim();
}

/// Every node the user can activate, anywhere under [root].
///
/// Nodes with [SemanticsNode.isMergedIntoParent] are skipped: they never
/// reach the browser on their own, their parent carries their data, and
/// widgets such as [FloatingActionButton] are built out of exactly that
/// (a [MergeSemantics] over a [Tooltip] over the button).
List<SemanticsNode> _controls(SemanticsNode root) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    if (!node.isMergedIntoParent &&
        (data.hasAction(SemanticsAction.tap) ||
            flags.isButton ||
            flags.isTextField ||
            flags.isLink ||
            flags.isSlider)) {
      found.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return found;
}

void main() {
  setUp(_seed);

  group('chart', () {
    testWidgets('summarises itself for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        MetricLineChart(
          labels: const ['Sep 29-Oct 5', 'Oct 6-12', 'Oct 13-19'],
          values: [
            for (var i = 0; i < 3; i++) {for (final m in metrics) m.key: 5},
          ],
          description: 'LinkedIn weekly totals, all employees',
          unit: 'week',
        ),
      );

      expect(
        find.bySemanticsLabel(
          'LinkedIn weekly totals, all employees, bar chart, 3 weeks, '
          '8 of 8 metrics shown',
        ),
        findsOne,
      );

      // Hiding a metric and switching to the line view both show up in it.
      await tester.tap(find.bySemanticsLabel('Likes'));
      await tester.tap(find.text('Line'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'LinkedIn weekly totals, all employees, line chart, 3 weeks, '
          '7 of 8 metrics shown',
        ),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('says so when there is nothing to plot', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const MetricLineChart(
          labels: [],
          values: [],
          description: 'LinkedIn weekly totals, all employees',
          unit: 'week',
        ),
      );
      expect(
        find.bySemanticsLabel(
          'LinkedIn weekly totals, all employees, bar chart, no data yet',
        ),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('legend items carry their state', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        MetricLineChart(
          labels: const ['Oct 6-12'],
          values: [
            {for (final m in metrics) m.key: 5},
          ],
          description: 'LinkedIn weekly totals, all employees',
          unit: 'week',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Likes')),
        isSemantics(
          label: 'Likes',
          hint: 'Shown. Activate to hide from the chart',
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('screens', () {
    testWidgets('employee rows name their switch, buttons and handle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const ManageEmployeesScreen());

      expect(find.bySemanticsLabel('Reorder Asha Menon'), findsOne);
      expect(find.byTooltip('Rename Asha Menon'), findsOne);
      expect(find.byTooltip('Remove Rahul Nair'), findsOne);

      // The name has to land on the switch node itself, not on a wrapper, or
      // the browser renders the control without an accessible name.
      final sw = tester.getSemantics(find.byType(Switch).first);
      expect(_name(sw), contains('Asha Menon active'));
      expect(
        sw,
        isSemantics(
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('week rows name their edit and delete buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const ManageWeeksScreen());
      expect(find.byTooltip('Rename Oct 6-12'), findsOne);
      expect(find.byTooltip('Delete Sep 29-Oct 5'), findsOne);
      expect(find.byTooltip('Add New Week'), findsOne);
      handle.dispose();
    });

    testWidgets('every metric field is named after metric and employee', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const DataEntryScreen());

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oct 6-12').last);
      await tester.pumpAndSettle();

      // Only Asha is active, so hers is the one card on the page.
      for (final m in metrics) {
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('${m.label} for Asha Menon'),
          ),
          isSemantics(isTextField: true),
          reason: '${m.label} should be named on the input itself',
        );
      }
      handle.dispose();
    });

    // Dashboard and Settings are left out: both reach `package:web` through
    // services/download.dart, which the VM test host cannot compile.
    testWidgets('no control reaches the tree unnamed', (tester) async {
      final handle = tester.ensureSemantics();
      for (final screen in <Widget>[
        const DataEntryScreen(),
        const ManageWeeksScreen(),
        const ManageEmployeesScreen(),
        MetricLineChart(
          labels: const ['Sep 29-Oct 5', 'Oct 6-12'],
          values: [
            for (var i = 0; i < 2; i++) {for (final m in metrics) m.key: 5},
          ],
          description: 'LinkedIn weekly totals, all employees',
          unit: 'week',
        ),
      ]) {
        await _pump(tester, screen);
        final unnamed = _controls(tester.getSemantics(find.byType(MaterialApp)))
            .where((n) => _name(n).isEmpty)
            .toList();
        expect(
          unnamed,
          isEmpty,
          reason:
              '${screen.runtimeType}: ${unnamed.length} unnamed control(s) '
              '${unnamed.map((n) => n.getSemanticsData())}',
        );
      }
      handle.dispose();
    });
  });
}
