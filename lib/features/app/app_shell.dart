import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/org/org_modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/modern_widgets.dart';
import '../org/org_session.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  List<_Tab> _tabs(OrgSession org) {
    switch (org.workspace) {
      case 'inventory':
        return const [
          _Tab('Home', Icons.warehouse_rounded, Icons.warehouse_outlined, '/inventory', 0),
          _Tab('Issue', Icons.assignment_rounded, Icons.assignment_outlined, '/inventory/imr', 1),
          _Tab('Transfer', Icons.swap_horiz_rounded, Icons.swap_horiz, '/inventory/transfers', 2),
          _Tab('Scrap', Icons.delete_sweep_rounded, Icons.delete_outline, '/inventory/scrap', 3),
          _Tab('More', Icons.grid_view_rounded, Icons.apps_outlined, '/more', 4),
        ];
      case 'project_management':
        return const [
          _Tab('Home', Icons.dashboard_rounded, Icons.dashboard_outlined, '/pms', 0),
          _Tab('Projects', Icons.folder_special_rounded, Icons.folder_outlined, '/pms/projects', 1),
          _Tab('Tasks', Icons.task_alt_rounded, Icons.checklist_outlined, '/pms/tasks', 2),
          _Tab('Approvals', Icons.verified_rounded, Icons.fact_check_outlined, '/pms/approvals', 3),
          _Tab('More', Icons.grid_view_rounded, Icons.apps_outlined, '/more', 4),
        ];
      default:
        return const [
          _Tab('Home', Icons.home_rounded, Icons.home_outlined, '/home', 0),
          _Tab('RR', Icons.request_quote_rounded, Icons.description_outlined, '/procurement/rr', 1),
          _Tab('Approvals', Icons.verified_rounded, Icons.verified_outlined, '/procurement/approvals', 2),
          _Tab('Orders', Icons.shopping_bag_rounded, Icons.shopping_cart_outlined, '/procurement/po', 3),
          _Tab('More', Icons.grid_view_rounded, Icons.apps_outlined, '/more', 4),
        ];
    }
  }

  int _index(String path, List<_Tab> tabs) {
    if (path.startsWith('/pms/settings') ||
        path.startsWith('/pms/templates') ||
        path.startsWith('/procurement/rc') ||
        path.startsWith('/procurement/rate-approvals') ||
        path.startsWith('/procurement/rr-status') ||
        path.startsWith('/dmr') ||
        path.startsWith('/notifications') ||
        path.startsWith('/billing')) {
      return tabs.length - 1;
    }
    for (var i = tabs.length - 1; i >= 0; i--) {
      if (path == tabs[i].path || path.startsWith('${tabs[i].path}/')) {
        if (tabs[i].path == '/more' && path != '/more') continue;
        return i;
      }
    }
    if (path.startsWith('/pms') && tabs.any((t) => t.path == '/pms')) {
      return 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgSession>();
    final location = GoRouterState.of(context).uri.path;
    final tabs = _tabs(org);
    final index = _index(location, tabs).clamp(0, tabs.length - 1);

    if (location == '/home' &&
        org.workspace != 'procurement' &&
        org.accessibleWorkspaces.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(workspaceHomePath(org.workspace));
      });
    }

    if (org.accessibleWorkspaces.isNotEmpty &&
        !org.canAccessWorkspace(org.workspace)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(workspaceHomePath(org.workspace));
      });
    }

    // Must match ModernBottomNav: 68 bar + 12 pad + system gesture inset.
    final navClearance =
        80 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: navClearance),
        child: child,
      ),
      bottomNavigationBar: ModernBottomNav(
        selectedIndex: index,
        onSelected: (i) {
          final target = tabs[i].path;
          if (location == target) return;
          context.go(target);
        },
        items: [
          for (final tab in tabs)
            ModernNavItem(
              label: tab.label,
              icon: tab.iconOutlined,
              selectedIcon: tab.iconFilled,
              color: AppTheme.colorAt(tab.colorIndex),
            ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(
    this.label,
    this.iconFilled,
    this.iconOutlined,
    this.path,
    this.colorIndex,
  );
  final String label;
  final IconData iconFilled;
  final IconData iconOutlined;
  final String path;
  final int colorIndex;
}

class WorkspaceSwitcherButton extends StatelessWidget {
  const WorkspaceSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgSession>();
    final enabled = org.accessibleWorkspaces;
    if (enabled.length < 2) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Switch workspace',
      icon: const Icon(Icons.workspaces_rounded),
      onSelected: (value) async {
        await org.setWorkspace(value);
        if (context.mounted) context.go(workspaceHomePath(value));
      },
      itemBuilder: (_) => [
        for (final key in enabled)
          PopupMenuItem(
            value: key,
            child: Row(
              children: [
                AppIconBadge(
                  icon: _workspaceIcon(key),
                  color: _workspaceColor(key),
                  size: 32,
                  iconSize: 16,
                ),
                const SizedBox(width: 10),
                Text(
                  workspaceLabels[key] ?? key,
                  style: TextStyle(
                    fontWeight: key == org.workspace ? FontWeight.w700 : FontWeight.w400,
                    color: key == org.workspace ? AppTheme.brand : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static IconData _workspaceIcon(String key) => switch (key) {
        'inventory' => Icons.warehouse_rounded,
        'project_management' => Icons.folder_special_rounded,
        _ => Icons.shopping_bag_rounded,
      };

  static Color _workspaceColor(String key) => switch (key) {
        'inventory' => AppTheme.success,
        'project_management' => AppTheme.accent,
        _ => AppTheme.warning,
      };
}

class MoreHubScreen extends StatelessWidget {
  const MoreHubScreen({super.key});

  static const _tiles = [
    _MoreTile('Requisitions', Icons.request_quote_rounded, '/procurement/rr', 1, 'procurement', 'requisition'),
    _MoreTile('RR Approvals', Icons.verified_rounded, '/procurement/approvals', 2, 'procurement', 'requisition'),
    _MoreTile('Rate Comparatives', Icons.analytics_rounded, '/procurement/rc', 3, 'procurement', 'rate_comparison'),
    _MoreTile('Rate Approvals', Icons.gavel_rounded, '/procurement/rate-approvals', 4, 'procurement', 'rate_comparison'),
    _MoreTile('Purchase Orders', Icons.shopping_bag_rounded, '/procurement/po', 5, 'procurement', 'purchase_order'),
    _MoreTile('RR Status', Icons.timeline_rounded, '/procurement/rr-status', 6, 'procurement', 'requisition'),
    _MoreTile('Create DMR', Icons.add_box_rounded, '/dmr/create', 0, 'procurement', 'dmr'),
    _MoreTile('DMR Status', Icons.local_shipping_rounded, '/dmr/status', 7, 'procurement', 'dmr'),
    _MoreTile('Inventory', Icons.warehouse_rounded, '/inventory', 0, 'inventory', 'inventory'),
    _MoreTile('Issued Material', Icons.assignment_rounded, '/inventory/imr', 1, 'inventory', 'material_issue'),
    _MoreTile('Intersite Transfer', Icons.swap_horiz_rounded, '/inventory/transfers', 2, 'inventory', 'inter_site_transfer'),
    _MoreTile('Scrap', Icons.delete_sweep_rounded, '/inventory/scrap', 3, 'inventory', 'scrape_disposal'),
    _MoreTile('Projects', Icons.folder_special_rounded, '/pms/projects', 1, 'project_management', 'projects'),
    _MoreTile('Tasks', Icons.task_alt_rounded, '/pms/tasks', 2, 'project_management', 'tasks'),
    _MoreTile('Templates', Icons.copy_all_rounded, '/pms/templates', 3, 'project_management', 'templates'),
    _MoreTile('Task Approvals', Icons.verified_rounded, '/pms/approvals', 4, 'project_management', 'task_progress'),
    _MoreTile('Notifications', Icons.notifications_active_rounded, '/notifications', 5, null, null),
    _MoreTile('Plans & Payments', Icons.credit_card_rounded, '/billing', 6, null, null),
    _MoreTile('Settings & Masters', Icons.settings_suggest_rounded, '/pms/settings', 7, null, null),
  ];

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgSession>();
    final visible = _tiles.where((t) {
      if (t.module == null) return true;
      return org.canUseSubmodule(t.module!, t.submodule!);
    }).toList();

    return Scaffold(
      extendBody: true,
      appBar: ModernAppBar(
        title: 'More',
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: GridView.builder(
        padding: AppTheme.pagePadding,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.7,
        ),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final t = visible[i];
          final color = AppTheme.colorAt(t.colorIndex);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push(t.path),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                  boxShadow: AppTheme.cardShadow,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.08),
                      Colors.white,
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIconBadge(icon: t.icon, color: color),
                    const SizedBox(height: 8),
                    Text(
                      t.title,
                      style: AppTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoreTile {
  const _MoreTile(
    this.title,
    this.icon,
    this.path,
    this.colorIndex,
    this.module,
    this.submodule,
  );
  final String title;
  final IconData icon;
  final String path;
  final int colorIndex;
  final String? module;
  final String? submodule;
}

int paginationTotalPages(Map<String, dynamic>? pagination) {
  final pages = pagination?['totalPages'];
  if (pages is num) return pages.toInt().clamp(1, 9999);
  return 1;
}
