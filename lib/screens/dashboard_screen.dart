import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models.dart';
import '../services/csv_export.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/metric_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _weekId;
  bool _monthly = false;

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final weeks = repo.weeks;
    final monthly = repo.monthlyTotals;
    // Default to the latest week; fall back if the selected one was deleted.
    if (_weekId == null || !weeks.any((w) => w.id == _weekId)) {
      _weekId = weeks.isEmpty ? null : weeks.last.id;
    }

    if (kDebugMode) debugPrint(repo.diagnostics()); // TEMPORARY logging
    final stale = repo.staleDemoWeeks;

    return PageBody(
      title: 'Dashboard',
      children: [
        if (stale.isNotEmpty) ...[
          AppCard(
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Pill('DEMO DATA', color: Color(0xFFE37400)),
                Text(
                  '${stale.length} demo weeks hold old oversized values '
                  '(per-employee numbers outside the sample limits), which '
                  'inflates the graph. Real weeks are not affected.',
                ),
                FilledButton.icon(
                  onPressed: () async {
                    var n = 0;
                    final ok = await guard(context, () async {
                      n = await repo.seedMockData();
                    });
                    if (ok && context.mounted) {
                      showSuccess(context, 'Regenerated $n demo weeks');
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate demo data'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle(
                'LinkedIn ${_monthly ? 'Monthly' : 'Weekly'} Totals — All Employees',
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppColors.primaryLight,
                        selectedForegroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.cardBorder),
                      ),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Weekly')),
                        ButtonSegment(value: true, label: Text('Monthly')),
                      ],
                      selected: {_monthly},
                      onSelectionChanged: (s) =>
                          setState(() => _monthly = s.first),
                    ),
                    MenuAnchor(
                      style: const MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(Colors.white),
                      ),
                      menuChildren: [
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.functions, size: 18),
                          onPressed: () => guard(
                            context,
                            () async => _monthly
                                ? exportMonthlyCsv()
                                : exportWeeklyCsv(),
                            success: 'CSV downloaded',
                          ),
                          child: Text(_monthly
                              ? 'Summary — totals per month'
                              : 'Summary — totals per week'),
                        ),
                        MenuItemButton(
                          leadingIcon:
                              const Icon(Icons.people_outline, size: 18),
                          onPressed: () => guard(
                            context,
                            () async => exportRawCsv(),
                            success: 'CSV downloaded',
                          ),
                          child: const Text(
                              'Employee-level — one row per employee per week'),
                        ),
                      ],
                      builder: (context, menu, _) => OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onPressed: weeks.isEmpty
                            ? null
                            : () => menu.isOpen ? menu.close() : menu.open(),
                        icon: const Icon(Icons.table_view_outlined, size: 18),
                        label: const Text('CSV'),
                      ),
                    ),
                  ],
                ),
              ),
              if (weeks.any((w) => w.isDemo)) ...[
                const SizedBox(height: 8),
                const _DemoNotice(
                  'Includes generated sample weeks. '
                  'Remove them in Settings → Sample Data.',
                ),
              ],
              const SizedBox(height: 16),
              if (_monthly)
                MetricLineChart(
                  labels: [for (final r in monthly) monthLabel.format(r.month)],
                  values: [for (final r in monthly) r.totals],
                  period: ChartPeriod.monthly,
                )
              else
                MetricLineChart(
                  labels: [for (final w in weeks) w.name],
                  values: [for (final w in weeks) repo.totalsFor(w.id)],
                  period: ChartPeriod.weekly,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _RequirementsCard(),
        const SizedBox(height: 24),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle(
                'Employee Breakdown',
                trailing: weeks.isEmpty
                    ? null
                    : WeekDropdown(
                        weeks: weeks,
                        value: _weekId,
                        onChanged: (id) => setState(() => _weekId = id),
                      ),
              ),
              const SizedBox(height: 20),
              if (_weekId == null)
                const EmptyState(
                  icon: Icons.table_chart_outlined,
                  message: 'Create a week and enter data to see the breakdown.',
                )
              else ...[
                if (weeks.firstWhere((w) => w.id == _weekId).isDemo) ...[
                  const _DemoNotice('This week contains generated sample values.'),
                  const SizedBox(height: 16),
                ],
                _Breakdown(entries: repo.entriesFor(_weekId!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class WeekDropdown extends StatelessWidget {
  const WeekDropdown({
    super.key,
    required this.weeks,
    required this.value,
    required this.onChanged,
  });

  final List<Week> weeks;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        key: ValueKey(value),
        isExpanded: true,
        dropdownColor: Colors.white,
        decoration: const InputDecoration(labelText: 'Week'),
        items: [
          for (final w in weeks.reversed)
            DropdownMenuItem(
              value: w.id,
              child: Text(w.isDemo ? '${w.name} · DEMO' : w.name),
            ),
        ],
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}

/// "DEMO DATA" badge with a short explanation.
class _DemoNotice extends StatelessWidget {
  const _DemoNotice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Pill('DEMO DATA', color: Color(0xFFE37400)),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard();

  static const _points = [
    ('X-axis', 'Weeks — each new week you add appears automatically'),
    ('Y-axis', 'The actual metric being analysed'),
    ('Values', 'Total performance of all employees combined for each week'),
    (
      'Future updates',
      'Enter new data week by week, totals and charts update automatically',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.card,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Requirements',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final (label, text) in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 10, 0),
                    child: Text(
                      '•',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$label: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: text,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Table (or cards on mobile) + per-employee chart for one week.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.entries});
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.edit_note,
        message:
            'No data entered for this week yet.\n'
            'Use Data Entry to add numbers.',
      );
    }
    final totals = sumEntries(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isMobile(context)
            ? _MobileBreakdown(entries: entries, totals: totals)
            : BreakdownTable(entries: entries, totals: totals),
        const SizedBox(height: 32),
        const Text(
          'Employee-wise comparison',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF424242),
          ),
        ),
        const SizedBox(height: 12),
        MetricLineChart(
          labels: [for (final e in entries) e.employeeName],
          values: [for (final e in entries) e.values],
        ),
      ],
    );
  }
}

class BreakdownTable extends StatelessWidget {
  const BreakdownTable({
    super.key,
    required this.entries,
    required this.totals,
  });
  final List<Entry> entries;
  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    TableRow row(
      String name,
      Map<String, int> v, {
      bool header = false,
      bool bold = false,
    }) {
      final style = TextStyle(
        fontSize: 13,
        fontWeight: header || bold ? FontWeight.w600 : FontWeight.w400,
        color: header ? AppColors.textSecondary : AppColors.textPrimary,
      );
      Widget cell(String t, {bool left = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          t,
          style: style,
          textAlign: left ? TextAlign.left : TextAlign.right,
        ),
      );
      return TableRow(
        decoration: BoxDecoration(
          color: header ? AppColors.card : Colors.white,
          border: const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        children: [
          cell(name, left: true),
          for (final m in metrics) cell(header ? m.short : fmt(v[m.key] ?? 0)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                columnWidths: const {0: IntrinsicColumnWidth(flex: 2)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  row('Employee Name', const {}, header: true),
                  for (final e in entries) row(e.employeeName, e.values),
                  row('Total', totals, bold: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileBreakdown extends StatelessWidget {
  const _MobileBreakdown({required this.entries, required this.totals});
  final List<Entry> entries;
  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    Widget card(
      String name,
      Map<String, int> v, {
      bool total = false,
    }) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: total ? AppColors.card : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 6,
            children: [
              for (final m in metrics)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.short,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        fmt(v[m.key] ?? 0),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        for (final e in entries) card(e.employeeName, e.values),
        card('Total', totals, total: true),
      ],
    );
  }
}
