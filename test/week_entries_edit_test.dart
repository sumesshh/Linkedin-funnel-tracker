import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkedin_dashboard/data/repository.dart';
import 'package:linkedin_dashboard/models.dart';
import 'package:linkedin_dashboard/widgets/week_entries_dialog.dart';

const _weekId = 'w1';
final _week = Week(
  id: _weekId,
  name: 'Jun 8–14',
  startDate: DateTime(2026, 6, 8),
  createdAt: DateTime(2026, 6, 8),
);

const _employees = [
  Employee(id: 'e0', name: 'Asha Menon', order: 1, isActive: true),
  Employee(id: 'e1', name: 'Rahul Nair', order: 2, isActive: true),
];

/// Distinct numbers per employee and metric, so a test matching on a value
/// cannot match the wrong cell.
Map<String, int> _values(int employee) => {
      for (final (i, m) in metrics.indexed) m.key: (employee + 1) * 100 + i,
    };

late FakeFirebaseFirestore db;
late Repository repo;

Future<void> _seed() async {
  db = FakeFirebaseFirestore();
  repo = Repository.instance..useFirestoreForTests(db);
  repo.employees = _employees;
  repo.allWeeks = [_week];
  repo.weeks = [_week];
  repo.entriesByWeek = {
    _weekId: [
      for (final (i, e) in _employees.indexed)
        Entry(
          weekId: _weekId,
          employeeId: e.id,
          employeeName: e.name,
          values: _values(i),
        ),
    ],
  };
  for (final (i, e) in _employees.indexed) {
    await db
        .collection('weeks')
        .doc(_weekId)
        .collection('entries')
        .doc(e.id)
        .set({
      'employeeName': e.name,
      ..._values(i),
      // A field this app does not know about: the merged write must keep it.
      'note': 'kept',
    });
  }
}

Future<Map<String, dynamic>> _stored(String employeeId) async {
  final d = await db
      .collection('weeks')
      .doc(_weekId)
      .collection('entries')
      .doc(employeeId)
      .get();
  return d.data()!;
}

Future<void> _openDialog(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showWeekEntriesDialog(context, _week),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The input for one metric of one employee, named the way a screen reader
/// announces it.
Finder _field(Metric m, Employee e) => find.descendant(
      of: find.bySemanticsLabel('${m.label} for ${e.name}'),
      matching: find.byType(TextField),
    );

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.ancestor(
      of: find.text('Save changes'),
      matching: find.byType(FilledButton),
    ));

void main() {
  final likes = metrics.firstWhere((m) => m.key == 'likes');
  final reach = metrics.firstWhere((m) => m.key == 'reach');

  setUp(_seed);

  testWidgets('opens with every stored number in an editable field',
      (tester) async {
    await _openDialog(tester);

    expect(find.text('Jun 8–14'), findsOneWidget);
    // 2 employees x 8 metrics.
    expect(find.byType(TextField), findsNWidgets(metrics.length * 2));
    expect(
      tester.widget<TextField>(_field(likes, _employees[0])).controller!.text,
      '${_values(0)['likes']}',
    );
    // Nothing edited yet, so there is nothing to save.
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('retotals as you type and saves only what changed',
      (tester) async {
    await _openDialog(tester);

    await tester.enterText(_field(likes, _employees[0]), '999');
    await tester.pump();

    // Total row follows the edit: 999 + Rahul's 202.
    expect(find.text('1,201'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing); // closed on save
    final asha = await _stored('e0');
    expect(asha['likes'], 999);
    expect(asha['reach'], _values(0)['reach']); // untouched metric
    expect(asha['note'], 'kept'); // merged, not overwritten
    expect(asha['updatedAt'], isA<Timestamp>());
    expect((await _stored('e1'))['likes'], _values(1)['likes']);
  });

  testWidgets('an emptied field saves as zero', (tester) async {
    await _openDialog(tester);

    await tester.enterText(_field(reach, _employees[1]), '');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect((await _stored('e1'))['reach'], 0);
  });

  testWidgets('cancelling edits asks before discarding them', (tester) async {
    await _openDialog(tester);

    await tester.enterText(_field(likes, _employees[0]), '7');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect((await _stored('e0'))['likes'], _values(0)['likes']);
  });

  testWidgets('a week with no entries still opens, read-only', (tester) async {
    repo.entriesByWeek = {};
    await _openDialog(tester);

    expect(find.text('No data entered for this week yet.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Save changes'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
