import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/week_dialog.dart';
import '../widgets/week_entries_dialog.dart';

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

  /// Opens the week's breakdown with every number editable in place.
  void _view(BuildContext context, Week week) {
    showWeekEntriesDialog(context, week);
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
          // Only while there is something to report: duplicate demo documents
          // the list is collapsing, or two visible weeks on one start date.
          if (repo.duplicateWeeks.isNotEmpty ||
              collidingWeekStarts(repo.allWeeks).isNotEmpty) ...[
            _DuplicateHint(
              hidden: repo.duplicateWeeks.length,
              collisions: collidingWeekStarts(repo.allWeeks),
            ),
            const SizedBox(height: 16),
          ],
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
                      // Named after the week, so a screen reader does not
                      // read out a column of identical "Rename" buttons.
                      IconButton(
                        tooltip: 'Rename ${w.name}',
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => _edit(context, w),
                      ),
                      IconButton(
                        tooltip: 'Delete ${w.name}',
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

/// Shown only while duplicates exist: demo weeks stored more than once (the
/// list shows one of each) and start dates carrying two visible weeks.
class _DuplicateHint extends StatelessWidget {
  const _DuplicateHint({required this.hidden, required this.collisions});

  final int hidden;
  final List<DateTime> collisions;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    return AppCard(
      color: AppColors.card,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.content_copy_outlined,
                size: 18, color: Color(0xFFE37400)),
            const SizedBox(width: 8),
            const Text('Duplicates hidden',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
          if (hidden > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$hidden duplicate demo week${hidden == 1 ? '' : 's'} '
              '${hidden == 1 ? 'is' : 'are'} stored in the database and left '
              'out of this list and of every total. Run the cleanup to delete '
              'them for good.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          if (collisions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Two weeks share a start date '
              '(${collisions.map(dateFmt.format).join(', ')}). Both are shown '
              'and both count towards that month — rename or delete one.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
