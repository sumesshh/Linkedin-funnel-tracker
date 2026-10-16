import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/week_dialog.dart';

const _createWeek = '__create__';

class DataEntryScreen extends StatefulWidget {
  const DataEntryScreen({super.key});

  @override
  State<DataEntryScreen> createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _weekId;

  /// controllers[employeeId][metricKey]
  final _controllers = <String, Map<String, TextEditingController>>{};
  bool _saving = false;

  Repository get _repo => Repository.instance;

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final m in _controllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _controllers.clear();
  }

  void _selectWeek(String id) {
    setState(() {
      _weekId = id;
      _disposeControllers();
    });
  }

  /// Controllers for [emp], created on first use and pre-filled with any
  /// saved numbers for the selected week (0 otherwise).
  Map<String, TextEditingController> _controllersFor(Employee emp) {
    return _controllers.putIfAbsent(emp.id, () {
      final saved = (_repo.entriesByWeek[_weekId] ?? const [])
          .where((e) => e.employeeId == emp.id)
          .firstOrNull;
      return {
        for (final m in metrics)
          m.key: TextEditingController(text: '${saved?[m.key] ?? 0}'),
      };
    });
  }

  Future<void> _onDropdown(String? value) async {
    if (value == null) return;
    if (value == _createWeek) {
      final id = await showWeekDialog(context);
      if (id != null && mounted) {
        showSuccess(context, 'Week created');
        _selectWeek(id);
      } else {
        setState(() {}); // reset dropdown back to the current week
      }
      return;
    }
    _selectWeek(value);
  }

  Future<void> _save(List<Employee> employees) async {
    if (!_formKey.currentState!.validate()) {
      showError(context, 'Please fix the highlighted fields');
      return;
    }
    setState(() => _saving = true);
    final values = {
      for (final emp in employees)
        emp: {
          for (final m in metrics)
            m.key: int.tryParse(_controllersFor(emp)[m.key]!.text.trim()) ?? 0,
        },
    };
    await guard(context, () => _repo.saveEntries(_weekId!, values),
        success: 'Data saved successfully');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _repo.weeks;
    if (_weekId != null && !weeks.any((w) => w.id == _weekId)) {
      _weekId = null;
      _disposeControllers();
    }
    final employees = _repo.activeEmployees;
    final mobile = isMobile(context);

    return Form(
      key: _formKey,
      child: PageBody(
        title: 'Enter Weekly Data',
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButtonFormField<String>(
                key: ValueKey('week-$_weekId-${weeks.length}'),
                initialValue: _weekId,
                isExpanded: true,
                dropdownColor: Colors.white,
                hint: const Text('Select a week'),
                decoration: const InputDecoration(labelText: 'Week'),
                items: [
                  const DropdownMenuItem(
                    value: _createWeek,
                    child: Text('＋ Create New Week',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500)),
                  ),
                  for (final w in weeks.reversed)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: _onDropdown,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_weekId == null)
            const EmptyState(
              icon: Icons.event_note_outlined,
              message: 'Select a week above, or create a new one,\n'
                  'to enter numbers for every employee.',
            )
          else if (employees.isEmpty)
            const EmptyState(
              icon: Icons.group_add_outlined,
              message: 'No active employees yet.\n'
                  'Add employees under Manage Employees first.',
            )
          else ...[
            for (final emp in employees) ...[
              _EmployeeCard(employee: emp, controllers: _controllersFor(emp)),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: mobile ? double.infinity : null,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(employees),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save All'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.controllers});
  final Employee employee;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(employee.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            const gap = 16.0;
            final cols = c.maxWidth < 520 ? 2 : 4;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 16,
              children: [
                for (final m in metrics)
                  SizedBox(
                    width: w,
                    child: _MetricField(
                        metric: m,
                        controller: controllers[m.key]!,
                        employeeName: employee.name),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField(
      {required this.metric,
      required this.controller,
      required this.employeeName});
  final Metric metric;
  final TextEditingController controller;

  /// Only for the field's screen-reader name: eight identically shaped boxes
  /// repeat per employee, so "Likes" alone does not say which card it is in.
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        // The label above is a plain Text, not part of the field's
        // decoration, so the input would otherwise reach assistive tech
        // unnamed. MergeSemantics puts the name on the input node itself
        // rather than on a wrapper around it.
        MergeSemantics(
          child: Semantics(
            label: '${metric.label} for $employeeName',
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              onTap: () {
                // Select the default "0" so typing replaces it.
                if (controller.text == '0') {
                  controller.selection =
                      TextSelection(baseOffset: 0, extentOffset: 1);
                }
              },
              validator: (v) {
                final n =
                    int.tryParse((v ?? '').trim().isEmpty ? '0' : v!.trim());
                if (n == null) return 'Numbers only';
                if (n < 0) return 'No negatives';
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
