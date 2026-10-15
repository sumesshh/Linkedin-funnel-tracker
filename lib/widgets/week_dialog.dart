import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Suggested label for a week starting on [start], e.g. "Jul 27–Aug 2".
String suggestWeekName(DateTime start) {
  final end = start.add(const Duration(days: 6));
  final f = DateFormat('MMM d');
  return start.month == end.month
      ? '${f.format(start)}–${end.day}'
      : '${f.format(start)}–${f.format(end)}';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day after the latest week ends, or this week's Monday.
DateTime nextWeekStart() {
  final weeks = Repository.instance.weeks;
  if (weeks.isNotEmpty) {
    return _dateOnly(weeks.last.startDate).add(const Duration(days: 7));
  }
  final now = _dateOnly(DateTime.now());
  return now.subtract(Duration(days: now.weekday - 1));
}

/// Create (week == null) or edit a week. Returns the week id on save.
Future<String?> showWeekDialog(BuildContext context, {Week? week}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _WeekDialog(week: week),
  );
}

class _WeekDialog extends StatefulWidget {
  const _WeekDialog({this.week});
  final Week? week;

  @override
  State<_WeekDialog> createState() => _WeekDialogState();
}

class _WeekDialogState extends State<_WeekDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _start;
  late final TextEditingController _name;
  late bool _nameEdited;
  bool _saving = false;

  bool get _isEdit => widget.week != null;

  @override
  void initState() {
    super.initState();
    _start = widget.week?.startDate ?? nextWeekStart();
    _name = TextEditingController(
        text: widget.week?.name ?? suggestWeekName(_start));
    _nameEdited = _isEdit;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Week start date',
    );
    if (picked == null) return;
    setState(() {
      _start = picked;
      if (!_nameEdited) _name.text = suggestWeekName(picked);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = Repository.instance;
    try {
      final String id;
      if (_isEdit) {
        id = widget.week!.id;
        await repo.updateWeek(id, _name.text, _start);
      } else {
        id = await repo.createWeek(_name.text, _start);
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, 'Could not save week: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Rename Week' : 'Create New Week'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Week name', hintText: 'e.g. July 27–Aug 1'),
                onChanged: (_) => _nameEdited = true,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Please enter a week name' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              const Text('Start date (sets chart order)',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('EEE, d MMM yyyy').format(_start)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
