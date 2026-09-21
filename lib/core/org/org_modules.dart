/// Mirrors backend MODULE_CATALOG and React `orgModules.js`.
const moduleCatalog = {
  'procurement': ['requisition', 'rate_comparison', 'purchase_order', 'dmr'],
  'inventory': ['inventory', 'material_issue', 'inter_site_transfer', 'scrape_disposal'],
  'project_management': ['projects', 'templates', 'tasks', 'task_progress'],
};

const workspaceOrder = ['procurement', 'inventory', 'project_management'];

const workspaceLabels = {
  'procurement': 'Procurement',
  'inventory': 'Inventory',
  'project_management': 'Project Management',
};

const submoduleLabels = {
  'requisition': 'Requisition',
  'rate_comparison': 'Rate comparison',
  'purchase_order': 'Purchase order',
  'dmr': 'DMR',
  'inventory': 'Inventory',
  'material_issue': 'Material issue',
  'inter_site_transfer': 'Intersite transfer',
  'scrape_disposal': 'Scrap disposal',
  'projects': 'Projects',
  'templates': 'Templates',
  'tasks': 'Tasks',
  'task_progress': 'Task progress',
};

Map<String, List<String>> get moduleCatalogMap =>
    Map<String, List<String>>.from(moduleCatalog);

Map<String, String> get workspaceLabelsMap =>
    Map<String, String>.from(workspaceLabels);

Map<String, String> get submoduleLabelsMap =>
    Map<String, String>.from(submoduleLabels);

Map<String, dynamic> buildDefaultModules() {
  final modules = <String, dynamic>{};
  moduleCatalog.forEach((key, subs) {
    modules[key] = {
      'enabled': false,
      'submodules': {for (final sub in subs) sub: false},
    };
  });
  return modules;
}

Map<String, dynamic> normalizeOrgModules(dynamic stored) {
  final source = stored is Map ? Map<String, dynamic>.from(stored) : <String, dynamic>{};
  final normalized = buildDefaultModules();
  for (final key in normalized.keys) {
    final storedModule =
        source[key] is Map ? Map<String, dynamic>.from(source[key] as Map) : <String, dynamic>{};
    if (storedModule['enabled'] is bool) {
      (normalized[key] as Map)['enabled'] = storedModule['enabled'] == true;
    }
    final storedSubs = storedModule['submodules'] is Map
        ? Map<String, dynamic>.from(storedModule['submodules'] as Map)
        : <String, dynamic>{};
    final subs = Map<String, dynamic>.from((normalized[key] as Map)['submodules'] as Map);
    for (final sub in subs.keys) {
      if (storedSubs[sub] is bool) {
        subs[sub] = storedSubs[sub] == true;
      }
    }
    (normalized[key] as Map)['submodules'] = subs;
  }
  return normalized;
}

/// Enable/disable a top-level module and cascade all of its submodules.
Map<String, dynamic> enableModuleFully(
  Map<String, dynamic>? modules,
  String moduleKey,
  bool enabled,
) {
  final next = normalizeOrgModules(modules);
  final subs = moduleCatalog[moduleKey] ?? const <String>[];
  next[moduleKey] = {
    'enabled': enabled,
    'submodules': {for (final sub in subs) sub: enabled},
  };
  return next;
}

/// Toggle one submodule; parent enabled = any submodule true.
Map<String, dynamic> setSubmoduleEnabled(
  Map<String, dynamic>? modules,
  String moduleKey,
  String subKey,
  bool enabled,
) {
  final next = normalizeOrgModules(modules);
  final mod = Map<String, dynamic>.from(next[moduleKey] as Map);
  final subs = Map<String, dynamic>.from(mod['submodules'] as Map);
  subs[subKey] = enabled;
  final anySub = subs.values.any((v) => v == true);
  mod['submodules'] = subs;
  mod['enabled'] = anySub || enabled;
  next[moduleKey] = mod;
  return next;
}

bool orgHasModule(Map<String, dynamic>? organization, String moduleKey, [String? submoduleKey]) {
  final modules = normalizeOrgModules(organization?['modules']);
  final mod = modules[moduleKey];
  if (mod is! Map || mod['enabled'] != true) return false;
  if (submoduleKey == null) return true;
  final subs = mod['submodules'];
  return subs is Map && subs[submoduleKey] == true;
}

const workspacePermissionModules = {
  'procurement': [
    'requisitionrequest',
    'ratecomparative',
    'requisitionorder',
    'dmrpurchaseorder',
    'dmrentry',
    'company',
    'vendor',
    'item',
    'uom',
    'gst',
    'brand',
    'category',
    'subcategory',
    'miscellaneousconfig',
    'location',
    'activity',
    'subactivity',
  ],
  'inventory': [
    'material-issue',
    'intersite-inventory',
    'scrape-disposal',
    'item',
    'uom',
    'gst',
    'brand',
    'category',
    'subcategory',
    'miscellaneousconfig',
  ],
  'project_management': [
    'project',
    'projecttemplate',
    'task',
    'taskprogress',
    'contractor',
  ],
};

Map<String, List<String>> get workspacePermissionModulesMap =>
    workspacePermissionModules.map((k, v) => MapEntry(k, List<String>.from(v)));

bool permissionListCanAnyModule(
  List<Map<String, dynamic>> modulePermissions,
  String module,
) {
  for (final mp in modulePermissions) {
    if (mp['module']?.toString() != module) continue;
    final perms = mp['permissions'];
    if (perms is! Map) return false;
    return perms.values.any((v) => v == true);
  }
  return false;
}

/// Workspaces the user may use (org enabled ∩ role has any product permission).
List<String> getUserWorkspaces(
  Map<String, dynamic>? organization,
  List<Map<String, dynamic>> modulePermissions, {
  bool isSuperAdmin = false,
}) {
  final orgEnabled = getEnabledWorkspaces(organization);
  if (isSuperAdmin) return orgEnabled;
  return orgEnabled.where((workspace) {
    final keys = workspacePermissionModules[workspace] ?? const <String>[];
    return keys.any((m) => permissionListCanAnyModule(modulePermissions, m));
  }).toList();
}

String resolveActiveWorkspaceForUser(
  Map<String, dynamic>? organization,
  String? preferred,
  List<Map<String, dynamic>> modulePermissions, {
  bool isSuperAdmin = false,
}) {
  final enabled = getUserWorkspaces(
    organization,
    modulePermissions,
    isSuperAdmin: isSuperAdmin,
  );
  if (enabled.isEmpty) return 'procurement';
  if (preferred != null && enabled.contains(preferred)) return preferred;
  return enabled.first;
}

/// Merge saved org modules: keep untouched products the editor cannot change.
Map<String, dynamic> mergeOrgModulesForSave({
  required Map<String, dynamic> edited,
  required Map<String, dynamic> existing,
  required Set<String> editableModuleKeys,
  bool allowAll = false,
}) {
  final next = normalizeOrgModules(edited);
  final prev = normalizeOrgModules(existing);
  if (allowAll) return next;
  for (final key in moduleCatalog.keys) {
    if (!editableModuleKeys.contains(key)) {
      next[key] = prev[key];
    }
  }
  return next;
}

bool pathRequiresWorkspace(String path) {
  if (path == '/home' ||
      path.startsWith('/procurement') ||
      path.startsWith('/dmr')) {
    return true;
  }
  if (path.startsWith('/inventory')) return true;
  if (path.startsWith('/pms') &&
      !path.startsWith('/pms/settings') &&
      path != '/pms/settings') {
    return true;
  }
  return false;
}

String? workspaceForPath(String path) {
  if (path == '/home' || path.startsWith('/procurement') || path.startsWith('/dmr')) {
    return 'procurement';
  }
  if (path.startsWith('/inventory')) return 'inventory';
  if (path.startsWith('/pms') && !path.startsWith('/pms/settings')) {
    return 'project_management';
  }
  return null;
}

List<String> getEnabledWorkspaces(Map<String, dynamic>? organization) {
  final modules = normalizeOrgModules(organization?['modules']);
  return workspaceOrder.where((key) {
    final mod = modules[key];
    return mod is Map && mod['enabled'] == true;
  }).toList();
}

String resolveActiveWorkspace(Map<String, dynamic>? organization, String? preferred) {
  final enabled = getEnabledWorkspaces(organization);
  if (enabled.isEmpty) return 'procurement';
  if (preferred != null && enabled.contains(preferred)) return preferred;
  return enabled.first;
}

String workspaceHomePath(String workspace) {
  switch (workspace) {
    case 'project_management':
      return '/pms';
    case 'inventory':
      return '/inventory';
    default:
      return '/home';
  }
}

Map<String, dynamic> buildApprovalPayload(int steps, String? step1, String? step2) {
  final n = steps.clamp(0, 2);
  final s1 = (step1 ?? '').trim();
  final s2 = (step2 ?? '').trim();
  return {
    'enabled': n > 0,
    'steps': n,
    'approvers': {
      'step1': n >= 1 && s1.isNotEmpty ? s1 : null,
      'step2': n == 2 && s2.isNotEmpty ? s2 : null,
    },
  };
}

Map<String, dynamic> emptyApprovalPayload() => {
      'enabled': false,
      'steps': 0,
      'approvers': {'step1': null, 'step2': null},
    };

bool anyModuleEnabled(Map<String, dynamic>? modules) {
  final normalized = normalizeOrgModules(modules);
  return normalized.values.any((m) => m is Map && m['enabled'] == true);
}
