/// Reads module rows out of `GET /permissions`, whether the API returns a
/// list or `{ permissions, grouped }`.
List<Map<String, dynamic>> permissionDefsFromResponse(Map<String, dynamic>? root) {
  final data = root?['data'];
  final rows = <Map<String, dynamic>>[];
  void addList(dynamic value) {
    if (value is! List) return;
    for (final item in value) {
      if (item is Map && item['module'] != null) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }
  }

  if (data is List) addList(data);
  if (data is Map) {
    addList(data['permissions']);
    final grouped = data['grouped'];
    if (grouped is Map) {
      for (final value in grouped.values) {
        addList(value);
      }
    }
  }
  return rows;
}

/// Builds the Modules screen rows from `GET /permissions`.
///
/// Super Admin roles created before the `module` permission key existed are
/// rejected by `GET /modules` (`module:read`). The permissions catalog is
/// available to a signed-in user and carries the same module names.
List<Map<String, dynamic>> modulesFromPermissionDefs(
  List<Map<String, dynamic>> defs,
) {
  final byModule = <String, Map<String, dynamic>>{};
  for (final row in defs) {
    final name = row['module']?.toString().trim().toLowerCase() ?? '';
    if (name.isEmpty) continue;
    final display = displayNameFromPermission(row) ?? titleCaseModule(name);
    final existing = byModule[name];
    if (existing == null) {
      byModule[name] = {
        'name': name,
        'displayName': display,
        'description': '',
      };
      continue;
    }
    final current = existing['displayName']?.toString() ?? '';
    if (current == titleCaseModule(name) && display != current) {
      existing['displayName'] = display;
    }
  }

  final items = byModule.values.toList()
    ..sort(
      (a, b) => (a['displayName']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['displayName']?.toString() ?? '').toLowerCase()),
    );
  return items;
}

String? displayNameFromPermission(Map<String, dynamic> row) {
  final desc = row['description']?.toString() ?? '';
  final match = RegExp(r'access for (.+)$', caseSensitive: false).firstMatch(desc);
  if (match == null) return null;
  var label = match.group(1)!.trim();
  const suffix = ' module';
  if (label.toLowerCase().endsWith(suffix)) {
    label = label.substring(0, label.length - suffix.length).trim();
  }
  return label.isEmpty ? null : label;
}

String titleCaseModule(String name) {
  return name
      .split(RegExp(r'[-_]'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
