import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_helpers.dart';
import '../../core/org/org_modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/modern_widgets.dart';
import '../auth/providers/auth_provider.dart';
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

class UserProfileButton extends StatelessWidget {
  const UserProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Profile',
      onPressed: () => _showProfile(context),
      icon: const Icon(Icons.account_circle_rounded),
    );
  }

  Future<void> _showProfile(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _ProfileSheet(
          onLogout: () async {
            Navigator.pop(sheetContext);
            await context.read<AuthProvider>().logout();
            if (context.mounted) context.go('/login');
          },
        );
      },
    );
  }
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  bool _detailsOpen = true;

  String? _organisationLabel(dynamic organisation) {
    if (organisation == null) return null;
    if (organisation is Map) {
      final name = organisation['organizationName'] ??
          organisation['organisationName'] ??
          organisation['name'];
      final text = name?.toString().trim() ?? '';
      if (text.isEmpty || looksLikeObjectId(text)) return null;
      return text;
    }
    final text = organisation.toString().trim();
    if (text.isEmpty || looksLikeObjectId(text)) return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final name = (user?.name ?? '').trim();
    final email = (user?.email ?? '').trim();
    final role = (user?.displayRole ?? '').trim();
    final org = _organisationLabel(user?.organisation);
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 720;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 480 : double.infinity),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileHeader(
                  initial: initial,
                  name: name.isEmpty ? 'Signed in' : name,
                  email: email,
                  expanded: _detailsOpen,
                  onTap: () => setState(() => _detailsOpen = !_detailsOpen),
                ),
                if (_detailsOpen) ...[
                  const SizedBox(height: 10),
                  _ProfileDetailTile(
                    icon: Icons.badge_outlined,
                    label: 'Role',
                    value: role.isEmpty ? 'User' : role,
                  ),
                  const SizedBox(height: 8),
                  _ProfileDetailTile(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: email.isEmpty ? 'Not available' : email,
                  ),
                  const SizedBox(height: 8),
                  const _ProfileDetailTile(
                    icon: Icons.verified_user_outlined,
                    label: 'Account',
                    value: 'Signed in',
                    valueColor: AppTheme.success,
                  ),
                  if (org != null) ...[
                    const SizedBox(height: 8),
                    _ProfileDetailTile(
                      icon: Icons.apartment_rounded,
                      label: 'Organisation',
                      value: org,
                    ),
                  ],
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.email,
    required this.expanded,
    required this.onTap,
  });

  final String initial;
  final String name;
  final String email;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.brandLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: AppTheme.brand.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.brand,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              Icon(
                expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: AppTheme.brand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileDetailTile extends StatelessWidget {
  const _ProfileDetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border.withValues(alpha: 0.9)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppTheme.brandLight,
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
