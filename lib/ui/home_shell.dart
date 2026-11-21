// Bottom navigation shell: Dashboard | Log | (+) | Program | More
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'dashboard/dashboard_screen.dart';
import 'log/log_screen.dart';
import 'log/add_food_sheet.dart';
import 'more/more_screen.dart';
import 'program/program_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Screenshot/debug hook: start on a given tab via
  // flutter run/build --dart-define=SHOT_TAB=log|program|more
  int _index = _initialTab();

  static int _initialTab() {
    // Plain switch — a const-map lookup crashes AOT builds when the
    // dart-define value is lost and the key misses.
    switch (String.fromEnvironment('SHOT_TAB')) {
      case 'log':
        return 1;
      case 'program':
        return 3;
      case 'more':
        return 4;
      default:
        return 0;
    }
  }

  static const _pages = [
    DashboardScreen(),
    LogScreen(),
    SizedBox.shrink(), // placeholder: FAB handles "+"
    ProgramScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: _pages[_index],
        ),
        floatingActionButton: _index == 2
            ? null
            : FloatingActionButton(
                backgroundColor: MtTheme.accent,
                child: const Icon(Icons.add, color: Color(0xFF0B1512)),
                onPressed: () => showAddFoodSheet(context),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: MtTheme.surface,
          shape: const CircularNotchedRectangle(),
          notchMargin: 6,
          child: Row(
            children: [
              _navItem(context, 0, Icons.dashboard_outlined, 'Dashboard'),
              _navItem(context, 1, Icons.restaurant_menu, 'Log'),
              const Spacer(),
              _navItem(context, 3, Icons.fitness_center, 'Program'),
              _navItem(context, 4, Icons.more_horiz, 'More'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, IconData icon, String label) =>
      Expanded(
        flex: i == 2 ? 2 : 3,
        child: i == 2
            ? const SizedBox.shrink()
            : InkWell(
                onTap: () => setState(() => _index = i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        color: _index == i
                            ? MtTheme.accent
                            : MtTheme.textDim,
                        size: 22),
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: _index == i
                                ? MtTheme.accent
                                : MtTheme.textDim)),
                  ],
                ),
              ),
      );
}
