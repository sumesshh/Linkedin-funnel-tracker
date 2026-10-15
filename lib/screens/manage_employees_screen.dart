import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ManageEmployeesScreen extends StatelessWidget {
  const ManageEmployeesScreen({super.key});

  Repository get _repo => Repository.instance;

  Future<void> _add(BuildContext context) async {
    final name = await showTextDialog(context,
        title: 'Add Employee', label: 'Employee name', actionLabel: 'Add');
    if (name == null || !context.mounted) return;
    await guard(context, () => _repo.addEmployee(name),
        success: '$name added');
  }

  Future<void> _rename(BuildContext context, Employee e) async {
    final name = await showTextDialog(context,
        title: 'Rename Employee',
        label: 'Employee name',
        actionLabel: 'Save',
        initial: e.name);
    if (name == null || name == e.name || !context.mounted) return;
    await guard(context, () => _repo.renameEmployee(e.id, name),
        success: 'Renamed to $name');
  }

  Future<void> _delete(BuildContext context, Employee e) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove employee',
      message:
          'Remove ${e.name}? Historical data in existing weeks will be kept.',
      actionLabel: 'Remove',
    );
    if (!ok || !context.mounted) return;
    await guard(context, () => _repo.deleteEmployee(e.id),
        success: '${e.name} removed');
  }

  @override
  Widget build(BuildContext context) {
    final employees = _repo.employees;

    return PageBody(
      title: 'Manage Employees',
      action: OutlinedButton.icon(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Employee'),
      ),
      children: [
        if (employees.isEmpty)
          const EmptyState(
            icon: Icons.group_outlined,
            message: 'No employees yet. Add your team to start tracking.',
          )
        else ...[
          const Text('Drag the handle to reorder. Order is used in charts '
              'and tables.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: employees.length,
            proxyDecorator: (child, _, _) =>
                Material(color: Colors.transparent, child: child),
            onReorderItem: (from, to) {
              final list = [...employees];
              list.insert(to, list.removeAt(from));
              guard(context, () => _repo.reorderEmployees(list));
            },
            itemBuilder: (context, i) {
              final e = employees[i];
              return Padding(
                key: ValueKey(e.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_indicator,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(e.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: e.isActive
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                )),
                            e.isActive
                                ? const Pill('Active', color: AppColors.success)
                                : const Pill('Inactive',
                                    color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: e.isActive
                            ? 'Mark inactive (hide from Data Entry)'
                            : 'Mark active',
                        child: Switch(
                          value: e.isActive,
                          activeTrackColor: AppColors.success,
                          onChanged: (v) => guard(
                              context, () => _repo.setEmployeeActive(e.id, v)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined,
                            color: AppColors.textSecondary),
                        onPressed: () => _rename(context, e),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        onPressed: () => _delete(context, e),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
