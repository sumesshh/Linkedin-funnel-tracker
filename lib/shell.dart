import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'screens/dashboard_screen.dart';
import 'screens/data_entry_screen.dart';
import 'screens/manage_employees_screen.dart';
import 'screens/manage_weeks_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

class _Dest {
  final IconData icon, selectedIcon;
  final String label, shortLabel;
  const _Dest(this.icon, this.selectedIcon, this.label, this.shortLabel);
}

const _dests = [
  _Dest(Icons.insert_chart_outlined, Icons.insert_chart, 'Dashboard', 'Dashboard'),
  _Dest(Icons.edit_outlined, Icons.edit, 'Data Entry', 'Entry'),
  _Dest(Icons.calendar_month_outlined, Icons.calendar_month, 'Manage Weeks', 'Weeks'),
  _Dest(Icons.group_outlined, Icons.group, 'Manage Employees', 'Employees'),
  _Dest(Icons.settings_outlined, Icons.settings, 'Settings', 'Settings'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // `?page=1` … `?page=4` opens a specific page (handy for bookmarks).
  int _index = (int.tryParse(Uri.base.queryParameters['page'] ?? '') ?? 0)
      .clamp(0, _dests.length - 1);
  bool _railHover = false;

  static final List<Widget Function()> _screens = [
    DashboardScreen.new,
    DataEntryScreen.new,
    ManageWeeksScreen.new,
    ManageEmployeesScreen.new,
    SettingsScreen.new,
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final repo = Repository.instance;

    final content = ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (repo.error != null) {
          return _Message(
            icon: Icons.cloud_off,
            text: 'Could not load data from Firestore.\n${repo.error}',
          );
        }
        if (!repo.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        // IndexedStack keeps unsaved Data Entry edits when switching pages.
        // Fresh (non-const) widget instances so the screens rebuild whenever
        // the repository notifies; identical const instances are skipped.
        return IndexedStack(index: _index, children: [
          for (final screen in _screens) screen(),
        ]);
      },
    );

    if (width < Breakpoints.mobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('LinkedIn Dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          shape: const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        drawer: Drawer(
          shape: const RoundedRectangleBorder(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LinkedIn Dashboard',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Rextech Studios',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      Container(width: 48, height: 3, color: AppColors.primary),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                for (var i = 0; i < _dests.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: ListTile(
                      selected: i == _index,
                      selectedColor: AppColors.primary,
                      selectedTileColor: AppColors.primaryLight,
                      iconColor: AppColors.textSecondary,
                      textColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      leading: Icon(
                          i == _index ? _dests[i].selectedIcon : _dests[i].icon),
                      title: Text(_dests[i].label),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _index = i);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        body: content,
      );
    }

    final desktop = width > Breakpoints.desktop;
    // Tablet: icon-only rail that expands to show labels on hover.
    final extended = !desktop && _railHover;

    final rail = NavigationRail(
      backgroundColor: AppColors.background,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      extended: extended,
      minWidth: 72,
      minExtendedWidth: 220,
      labelType: desktop ? NavigationRailLabelType.all : NavigationRailLabelType.none,
      indicatorColor: AppColors.primaryLight,
      selectedIconTheme: const IconThemeData(color: AppColors.primary),
      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
      selectedLabelTextStyle: const TextStyle(
          color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      groupAlignment: -0.85,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        // Decorative "in" monogram; without this a screen reader reads out
        // the word "in" before the navigation items.
        child: ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('in',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
          ),
        ),
      ),
      destinations: [
        for (final d in _dests)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(desktop ? d.shortLabel : d.label),
          ),
      ],
    );

    final body = Row(
      children: [
        // On tablet the rail floats over a fixed 72px slot, so expanding it
        // on hover overlays the content instead of reflowing it.
        desktop ? rail : const SizedBox(width: 72),
        const VerticalDivider(width: 1, color: AppColors.divider),
        Expanded(child: content),
      ],
    );

    return Scaffold(
      body: desktop
          ? body
          : Stack(children: [
              body,
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _railHover = true),
                  onExit: (_) => setState(() => _railHover = false),
                  child: Material(
                    elevation: extended ? 4 : 0,
                    color: AppColors.background,
                    child: rail,
                  ),
                ),
              ),
            ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}
