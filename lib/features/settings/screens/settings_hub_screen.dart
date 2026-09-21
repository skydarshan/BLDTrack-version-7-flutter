import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../utils/permissions.dart';

/// Mobile equivalent of React top-right Administration dropdown.
class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  List<SettingsNavItem> _visible(
    List<SettingsNavItem> items,
    Permissions perms,
  ) {
    return items.where((item) {
      if (item.permission == null) return true;
      return perms.canAny(item.permission!) || perms.isSuperAdmin;
    }).toList();
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<SettingsNavItem> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
              fontSize: 13,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  ListTile(
                    leading: AppIconBadge(
                      icon: items[i].icon,
                      color: AppTheme.colorAt(i),
                      size: 38,
                      iconSize: 18,
                    ),
                    title: Text(items[i].label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(items[i].path),
                  ),
                  if (i < items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final perms = Permissions(user);
    final userMgmt = _visible(SettingsNav.userManagement, perms);
    final masters = _visible(SettingsNav.masters, perms);
    final other = _visible(SettingsNav.other, perms);

    return Scaffold(
      extendBody: true,
      appBar: ModernAppBar(
        title: 'Settings',
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: AppTheme.brandGradient,
              boxShadow: AppTheme.softShadow,
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  child: Text(
                    (user?.name.isNotEmpty == true ? user!.name[0] : 'U').toUpperCase(),
                    style: AppTheme.headlineSmall.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'User',
                        style: AppTheme.titleMedium.copyWith(color: Colors.white),
                      ),
                      Text(
                        user?.displayRole ?? 'User',
                        style: AppTheme.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      Text(
                        user?.email ?? '',
                        style: AppTheme.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _section(context, title: 'ADMINISTRATION', items: userMgmt),
          _section(context, title: 'MASTERS', items: masters),
          _section(context, title: 'OTHER', items: other),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: AppIconBadge(
                    icon: Icons.copy_all_rounded,
                    color: AppTheme.accent,
                  ),
                  title: const Text('Project Templates'),
                  subtitle: const Text('PMS templates'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/pms/templates'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: AppIconBadge(
                    icon: Icons.mail_rounded,
                    color: AppTheme.colorAt(4),
                  ),
                  title: const Text('App Settings'),
                  subtitle: const Text('Notification email & preferences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pms/settings/app'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout, color: AppTheme.danger),
            label: const Text(
              'Logout',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}
