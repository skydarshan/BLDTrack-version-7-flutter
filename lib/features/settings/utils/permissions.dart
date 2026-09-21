import 'package:flutter/material.dart';

import '../../../core/org/org_modules.dart';
import '../../auth/models/user_model.dart';

/// Mirrors React `usePermissions` — reads `user.role.modulePermissions`.
class Permissions {
  Permissions(this.user);

  final UserModel? user;

  List<Map<String, dynamic>> get modulePermissions {
    final role = user?.role;
    if (role is! Map) return const [];
    final list = role['modulePermissions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  bool can(String module, String action) {
    for (final mp in modulePermissions) {
      if (mp['module']?.toString() != module) continue;
      final perms = mp['permissions'];
      if (perms is Map) return perms[action] == true;
      return false;
    }
    return false;
  }

  bool canAny(String module) {
    for (final mp in modulePermissions) {
      if (mp['module']?.toString() != module) continue;
      final perms = mp['permissions'];
      if (perms is! Map) return false;
      return perms.values.any((v) => v == true);
    }
    return false;
  }

  bool hasWorkspaceAccess(String workspace, Map<String, dynamic>? organization) {
    return accessibleWorkspaces(organization).contains(workspace);
  }

  List<String> accessibleWorkspaces(Map<String, dynamic>? organization) {
    return getUserWorkspaces(
      organization,
      modulePermissions,
      isSuperAdmin: isSuperAdmin,
    );
  }

  /// Role-permission modules the user may assign when editing roles.
  Set<String> editablePermissionModules(Map<String, dynamic>? organization) {
    if (isSuperAdmin) {
      return workspacePermissionModules.values
          .expand((list) => list)
          .toSet()
        ..addAll(['user', 'role', 'organization', 'subscription', 'auditlog']);
    }
    final out = <String>{'user', 'role', 'organization', 'subscription', 'auditlog'};
    for (final ws in accessibleWorkspaces(organization)) {
      out.addAll(workspacePermissionModules[ws] ?? const []);
    }
    return out;
  }

  /// Org product modules the user may toggle in Organization settings.
  Set<String> editableOrgModuleKeys(Map<String, dynamic>? organization) {
    if (isSuperAdmin) return moduleCatalog.keys.toSet();
    return accessibleWorkspaces(organization).toSet();
  }

  bool get isSuperAdmin {
    final name = (user?.roleName ?? '').trim().toLowerCase();
    if (name == 'super admin') return true;
    final role = user?.role;
    if (role is Map) {
      return (role['name']?.toString() ?? '').trim().toLowerCase() == 'super admin';
    }
    return false;
  }
}

/// Menu entries for Settings hub (React user-dropdown masters).
class SettingsNavItem {
  const SettingsNavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
  });

  final String path;
  final String label;
  final IconData icon;
  final String? permission;
}

class SettingsNav {
  static const userManagement = <SettingsNavItem>[
    SettingsNavItem(
      path: '/pms/settings/users',
      label: 'Users',
      icon: Icons.people_outline,
      permission: 'user',
    ),
    SettingsNavItem(
      path: '/pms/settings/roles',
      label: 'Roles & Permissions',
      icon: Icons.shield_outlined,
      permission: 'role',
    ),
    SettingsNavItem(
      path: '/pms/settings/organization',
      label: 'Organization',
      icon: Icons.business_outlined,
      permission: 'organization',
    ),
  ];

  static const masters = <SettingsNavItem>[
    SettingsNavItem(
      path: '/pms/settings/locations',
      label: 'Locations',
      icon: Icons.place_outlined,
      permission: 'location',
    ),
    SettingsNavItem(
      path: '/pms/settings/companies',
      label: 'Companies',
      icon: Icons.apartment_outlined,
      permission: 'company',
    ),
    SettingsNavItem(
      path: '/pms/settings/sites',
      label: 'Sites',
      icon: Icons.account_tree_outlined,
      permission: 'site',
    ),
    SettingsNavItem(
      path: '/pms/settings/site-staff',
      label: 'Site Staff',
      icon: Icons.badge_outlined,
      permission: 'sitestaff',
    ),
    SettingsNavItem(
      path: '/pms/settings/contractors',
      label: 'Contractors',
      icon: Icons.engineering_outlined,
      permission: 'contractor',
    ),
    SettingsNavItem(
      path: '/pms/settings/activities',
      label: 'Activities',
      icon: Icons.task_alt_outlined,
      permission: 'activity',
    ),
    SettingsNavItem(
      path: '/pms/settings/sub-activities',
      label: 'Sub Activities',
      icon: Icons.list_alt_outlined,
      permission: 'subactivity',
    ),
    SettingsNavItem(
      path: '/pms/settings/uoms',
      label: 'UOMs',
      icon: Icons.straighten_outlined,
      permission: 'uom',
    ),
    SettingsNavItem(
      path: '/pms/settings/gsts',
      label: 'GST',
      icon: Icons.percent,
      permission: 'gst',
    ),
    SettingsNavItem(
      path: '/pms/settings/brands',
      label: 'Brands',
      icon: Icons.sell_outlined,
      permission: 'brand',
    ),
    SettingsNavItem(
      path: '/pms/settings/categories',
      label: 'Categories',
      icon: Icons.folder_outlined,
      permission: 'category',
    ),
    SettingsNavItem(
      path: '/pms/settings/sub-categories',
      label: 'Sub Categories',
      icon: Icons.folder_open_outlined,
      permission: 'subcategory',
    ),
    SettingsNavItem(
      path: '/pms/settings/vendors',
      label: 'Vendors',
      icon: Icons.storefront_outlined,
      permission: 'vendor',
    ),
    SettingsNavItem(
      path: '/pms/settings/items',
      label: 'Items',
      icon: Icons.inventory_2_outlined,
      permission: 'item',
    ),
    SettingsNavItem(
      path: '/pms/settings/misc-configs',
      label: 'Misc Configs',
      icon: Icons.tune,
      permission: 'miscellaneousconfig',
    ),
  ];

  static const other = <SettingsNavItem>[
    SettingsNavItem(
      path: '/pms/settings/audit-logs',
      label: 'Audit Logs',
      icon: Icons.history,
      permission: 'auditlog',
    ),
  ];
}
