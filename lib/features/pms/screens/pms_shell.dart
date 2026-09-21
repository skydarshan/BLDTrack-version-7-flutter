import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-nav shell for PMS + Settings routes.
class PmsShell extends StatelessWidget {
  const PmsShell({super.key, required this.child});

  final Widget child;

  static const _tabs = <_PmsTab>[
    _PmsTab(label: 'Home', icon: Icons.home_outlined, path: '/pms'),
    _PmsTab(label: 'Projects', icon: Icons.folder_outlined, path: '/pms/projects'),
    _PmsTab(label: 'Tasks', icon: Icons.checklist_outlined, path: '/pms/tasks'),
    _PmsTab(
      label: 'Approvals',
      icon: Icons.fact_check_outlined,
      path: '/pms/approvals',
    ),
    _PmsTab(
      label: 'Settings',
      icon: Icons.settings_outlined,
      path: '/pms/settings',
    ),
  ];

  int _indexForPath(String path) {
    if (path.startsWith('/pms/projects')) return 1;
    if (path.startsWith('/pms/tasks')) return 2;
    if (path.startsWith('/pms/approvals')) return 3;
    if (path.startsWith('/pms/settings') || path.startsWith('/pms/templates')) {
      return 4;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexForPath(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          final target = _tabs[i].path;
          if (location == target) return;
          context.go(target);
        },
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _PmsTab {
  const _PmsTab({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;
}
