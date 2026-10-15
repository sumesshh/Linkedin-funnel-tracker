import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/week_dialog.dart';
import 'dashboard_screen.dart' show BreakdownTable;

class ManageWeeksScreen extends StatelessWidget {
  const ManageWeeksScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final id = await showWeekDialog(context);
    if (id != null && context.mounted) showSuccess(context, 'Week created');
  }

  Future<void> _edit(BuildContext context, Week week) async {
    final id = await showWeekDialog(context, week: week);
    if (id != null && context.mounted) showSuccess(context, 'Week updated');
  }

  void _view(BuildContext context, Week week) {
    final entries = Repository.instance.entriesFor(week.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(week.name),
        content: SizedBox(
          width: 900,
          child: entries.isEmpty
              ? const Text(
                  'No data entered for this week yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              : SingleChildScrollView(
                  child: BreakdownTable(
                    entries: entries,
                    totals: sumEntries(entries),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Week week) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete week',
      message:
          'Delete ${week.name}? This removes all employee data for this '
          'week. Cannot be undone.',
      actionLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    await guard(
      context,
      () => Repository.instance.deleteWeek(week.id),
      success: '${week.name} deleted',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final weeks = repo.weeks;
    final dateFmt = DateFormat('d MMM yyyy');

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add New Week',
        shape: const CircleBorder(),
        onPressed: () => _add(context),
        child: const Icon(Icons.add),
      ),
      body: PageBody(
        title: 'Manage Weeks',
        bottomPadding: 96,
        children: [
          if (weeks.isEmpty)
            const EmptyState(
              icon: Icons.date_range_outlined,
              message: 'No weeks yet. Tap ＋ to add your first week.',
            ),
          for (final w in weeks) ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _view(context, w),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  w.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (w.isDemo)
                                  const Pill('DEMO DATA',
                                      color: Color(0xFFE37400)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _enteredLabel(
                                repo.entriesByWeek[w.id]?.length ?? 0,
                              ),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Starts ${dateFmt.format(w.startDate)}'
                              '${w.createdAt == null ? '' : '  ·  Created ${dateFmt.format(w.createdAt!)}'}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => _edit(context, w),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                        ),
                        onPressed: () => _delete(context, w),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  static String _enteredLabel(int n) =>
      '$n employee${n == 1 ? '' : 's'} entered';
}
