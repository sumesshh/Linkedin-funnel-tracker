import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Opens [week]'s breakdown with every number editable in place. Resolves to
/// true once the edits are saved.
Future<bool?> showWeekEntriesDialog(BuildContext context, Week week) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // edits in progress are easy to lose
    builder: (_) => _WeekEntriesDialog(week: week),
  );
}

class _WeekEntriesDialog extends StatefulWidget {
  const _WeekEntriesDialog({required this.week});
  final Week week;

  @override
  State<_WeekEntriesDialog> createState() => _WeekEntriesDialogState();
}

class _WeekEntriesDialogState extends State<_WeekEntriesDialog> {
  /// The week's rows as they were when the dialog opened. Kept as a snapshot
  /// so a background Firestore update cannot move a row out from under the
  /// cursor mid-edit.
  late final List<Entry> _rows;

  /// _controllers[employeeId][metricKey]
  late final Map<String, Map<String, TextEditingController>> _controllers;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = Repository.instance.entriesFor(widget.week.id);
    _controllers = {
      for (final e in _rows)
        e.employeeId: {
          for (final m in metrics)
            m.key: TextEditingController(text: '${e[m.key]}'),
        },
    };
  }

  @override
  void dispose() {
    for (final row in _controllers.values) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  int _value(String employeeId, String key) =>
      int.tryParse(_controllers[employeeId]![key]!.text.trim()) ?? 0;

  /// The rows carrying what is currently typed into them.
  List<Entry> get _edited => [
        for (final e in _rows)
          Entry(
            weekId: e.weekId,
            employeeId: e.employeeId,
            employeeName: e.employeeName,
            values: {
              for (final m in metrics) m.key: _value(e.employeeId, m.key),
            },
          ),
      ];

  bool get _dirty => _rows.any((e) =>
      metrics.any((m) => _value(e.employeeId, m.key) != e[m.key]));

  Future<void> _close() async {
    if (_dirty) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard changes?',
        message: 'Your edits to ${widget.week.name} have not been saved.',
        actionLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await guard(
      context,
      () => Repository.instance.saveEntryValues(widget.week.id, _edited),
      success: '${widget.week.name} updated',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _rows.isEmpty;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.week.name),
          if (!empty) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap any number to edit it, then Save changes.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 900,
        child: empty
            ? const Text(
                'No data entered for this week yet.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : SingleChildScrollView(
                child: _EditableBreakdown(
                  rows: _rows,
                  controllers: _controllers,
                  totals: sumEntries(_edited),
                  enabled: !_saving,
                  onChanged: () => setState(() {}),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _close,
          child: Text(empty ? 'Close' : 'Cancel'),
        ),
        if (!empty)
          FilledButton(
            onPressed: _saving || !_dirty ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save changes'),
          ),
      ],
    );
  }
}

/// The breakdown table with an input per metric cell. Column widths are fixed
/// rather than intrinsic: a text field has no natural width to measure.
class _EditableBreakdown extends StatelessWidget {
  const _EditableBreakdown({
    required this.rows,
    required this.controllers,
    required this.totals,
    required this.enabled,
    required this.onChanged,
  });

  final List<Entry> rows;
  final Map<String, Map<String, TextEditingController>> controllers;
  final Map<String, int> totals;
  final bool enabled;
  final VoidCallback onChanged;

  static const _nameWidth = 180.0;
  static const _valueWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13);

    Widget label(String t, TextStyle s, {bool left = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            t,
            style: s,
            textAlign: left ? TextAlign.left : TextAlign.right,
          ),
        );

    TableRow headerRow() => TableRow(
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          children: [
            label('Employee Name', _bold(AppColors.textSecondary), left: true),
            for (final m in metrics)
              label(m.short, _bold(AppColors.textSecondary)),
          ],
        );

    TableRow entryRow(Entry e) => TableRow(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          children: [
            label(e.employeeName, style, left: true),
            for (final m in metrics)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 6),
                child: _ValueField(
                  controller: controllers[e.employeeId]![m.key]!,
                  // Eight identical boxes repeat per row, so the metric alone
                  // does not say which row the field is in.
                  semanticsLabel: '${m.label} for ${e.employeeName}',
                  enabled: enabled,
                  onChanged: onChanged,
                ),
              ),
          ],
        );

    TableRow totalRow() => TableRow(
          decoration: const BoxDecoration(color: Colors.white),
          children: [
            label('Total', _bold(AppColors.textPrimary), left: true),
            for (final m in metrics)
              label(fmt(totals[m.key] ?? 0), _bold(AppColors.textPrimary)),
          ],
        );

    return LayoutBuilder(
      builder: (context, c) {
        final width = _nameWidth + _valueWidth * metrics.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width < c.maxWidth ? c.maxWidth : width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Table(
                columnWidths: {
                  0: const FlexColumnWidth(),
                  for (var i = 1; i <= metrics.length; i++)
                    i: const FixedColumnWidth(_valueWidth),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  headerRow(),
                  for (final e in rows) entryRow(e),
                  totalRow(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static TextStyle _bold(Color c) =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c);
}

class _ValueField extends StatelessWidget {
  const _ValueField({
    required this.controller,
    required this.semanticsLabel,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String semanticsLabel;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: c, width: w),
        );

    // Merged so the name lands on the input node itself: left on a wrapper
    // node, the browser still renders the field with no accessible name.
    return MergeSemantics(
      child: Semantics(
        label: semanticsLabel,
        child: TextField(
          controller: controller,
          enabled: enabled,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: border(AppColors.cardBorder),
            enabledBorder: border(AppColors.divider),
            focusedBorder: border(AppColors.primary, 1.5),
            disabledBorder: border(AppColors.divider),
          ),
          // Select what is there so typing replaces the number instead of
          // appending a digit to it.
          onTap: () => controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}
