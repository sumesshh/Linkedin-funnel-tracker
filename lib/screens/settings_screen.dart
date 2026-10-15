import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../services/backup.dart';
import '../services/csv_export.dart';
import '../services/download.dart';
import '../services/pdf_report.dart';
import '../theme.dart';
import '../widgets/common.dart';

const appVersion = '1.0.0';
const meetLink = 'https://meet.google.com/ihv-vceb-siw';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DateTime? _month;
  bool _generating = false;
  bool _importing = false;

  Future<void> _downloadReport() async {
    setState(() => _generating = true);
    await guard(context, () => downloadMonthlyReport(_month!),
        success: 'Report ready');
    if (mounted) setState(() => _generating = false);
  }

  Future<void> _import() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import data'),
        content: const SizedBox(
          width: 380,
          child: Text(
              'Records in the file will be written to the database. Anything '
              'with the same ID is overwritten; everything else is kept.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose file')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final data = await pickJsonFile();
      if (data == null || !mounted) return;
      setState(() => _importing = true);
      final r = await Repository.instance.importData(data);
      if (mounted) {
        showSuccess(context,
            'Imported ${r.employees} employees, ${r.weeks} weeks, ${r.entries} entries');
      }
    } catch (e) {
      if (mounted) showError(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = reportMonths(Repository.instance.weeks);
    if (_month == null || !months.contains(_month)) {
      _month = months.firstOrNull;
    }

    return PageBody(
      title: 'Settings',
      children: [
        _section(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Monthly PDF Report',
          children: [
            const Text(
              'Cover, monthly summary, weekly totals chart, a section per '
              'week and a raw data table you can paste into Google Sheets.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (months.isEmpty)
              const Text('Add weeks with data to generate a report.',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<DateTime>(
                      key: ValueKey(_month),
                      initialValue: _month,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                              value: m,
                              child: Text(DateFormat('MMMM yyyy').format(m))),
                      ],
                      onChanged: (m) => setState(() => _month = m),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _generating ? null : _downloadReport,
                    icon: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download_outlined),
                    label: const Text('Download Monthly Report'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        _section(
          icon: Icons.table_view_outlined,
          title: 'Spreadsheet Export (CSV)',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, export) in [
                  ('Weekly Totals', exportWeeklyCsv),
                  ('Monthly Totals', exportMonthlyCsv),
                  ('Raw Data (all employees)', exportRawCsv),
                ])
                  OutlinedButton.icon(
                    onPressed: () => guard(context, () async => export(),
                        success: 'CSV downloaded'),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(label),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'To chart it in Google Sheets: File → Import → Upload the CSV, '
              'select the table, then Insert → Chart (choose "Smooth line chart").',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _section(
          icon: Icons.backup_outlined,
          title: 'Data Backup',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => guard(context, () async => exportJson(),
                      success: 'Backup downloaded'),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export All Data (JSON)'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondaryButton,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  onPressed: _importing ? null : _import,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_importing ? 'Importing…' : 'Import Data (JSON)'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Export regularly as backup. Browser data is safe in Firebase '
              'but export gives you a local copy.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _section(
          icon: Icons.science_outlined,
          title: 'Sample Data',
          children: [
            const Text(
              'Adds 5 months of DEMO DATA weekly entries for the active '
              'employees, before your earliest real week, so the charts have '
              'history to show. Per employee per week: posts 0–5 (0 for '
              'repost-only accounts), comments 0–30, likes 0–150, reach '
              '100–950, profile views 0–300, DMs 0–15, enquiries 0–10. '
              'Generating again replaces the previous demo weeks; real weeks '
              'are never changed. Remove it before using the reports for real.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    var n = 0;
                    final ok = await guard(context, () async {
                      n = await Repository.instance.seedMockData();
                    });
                    if (ok && context.mounted) {
                      showSuccess(context, 'Generated $n demo weeks');
                    }
                  },
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Generate / Reset Demo Data'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    var n = 0;
                    final ok = await guard(context, () async {
                      n = await Repository.instance.clearMockData();
                    });
                    if (ok && context.mounted) {
                      showSuccess(context, 'Removed $n demo weeks');
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove Demo Data'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _section(
          icon: Icons.videocam_outlined,
          title: 'Team Meeting',
          children: [
            const SelectableText(
              meetLink,
              style: TextStyle(color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => openUrl(meetLink),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Join Google Meet'),
                ),
                OutlinedButton.icon(
                  onPressed: () => guard(context, () => copyText(meetLink),
                      success: 'Meeting link copied'),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy Link'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _section(
          icon: Icons.info_outline,
          title: 'About',
          children: const [
            Text('LinkedIn Analytics Dashboard',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Built for Rextech Studios',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('Version $appVersion',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            CardTitle(title),
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
