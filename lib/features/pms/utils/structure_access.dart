import '../../../core/network/api_helpers.dart';
import '../../../core/org/org_modules.dart';
import '../../org/org_session.dart';
import '../../settings/utils/permissions.dart';
import '../widgets/pickers.dart';

/// The six structure node types. Building and external area sit at the top.
const structureNodeTypeLabels = <String, String>{
  'building': 'Building',
  'floor': 'Floor',
  'core': 'Core',
  'unit': 'Unit',
  'common_area': 'Common area',
  'external_area': 'External area',
};

/// GET /structure and /structure/resolve stay available for the task picker
/// when Structure, Tasks, or Progress Model is enabled.
bool orgCanReadStructure(Map<String, dynamic>? organization) {
  return orgHasModule(organization, 'project_management', 'structure') ||
      orgHasModule(organization, 'project_management', 'tasks') ||
      orgHasModule(organization, 'project_management', 'progress_model');
}

/// projectstructure:read, or any task action that is allowed to read the tree.
bool userCanReadStructure(Permissions perms) {
  return perms.isSuperAdmin ||
      perms.can('projectstructure', 'read') ||
      perms.can('task', 'read') ||
      perms.can('task', 'create') ||
      perms.can('task', 'update');
}

bool showStructurePicker(OrgSession org, Permissions perms) {
  return orgCanReadStructure(org.organization) && userCanReadStructure(perms);
}

/// Structure tab: submodule on, and the user can read Project Structure.
bool showStructureEditor(OrgSession org, Permissions perms) {
  return org.hasModule('project_management', 'structure') &&
      (perms.isSuperAdmin || perms.can('projectstructure', 'read'));
}

bool canStructureAction(Permissions perms, String action) {
  return perms.isSuperAdmin || perms.can('projectstructure', action);
}

/// Progress Model tab: submodule on, and projectmodel:read.
bool showProgressModelTab(OrgSession org, Permissions perms) {
  return org.hasModule('project_management', 'progress_model') &&
      (perms.isSuperAdmin || perms.can('projectmodel', 'read'));
}

/// Role editor rows from the structure guide.
///
/// Project Structure and Progress Model appear while Project Management is on.
/// A row already stored on the role stays visible so a save does not drop it.
bool offerRolePermissionModule(
  String module,
  Map<String, dynamic>? organization, {
  required bool alreadyOnRole,
}) {
  if (module == 'projectstructure' || module == 'projectmodel') {
    return alreadyOnRole || orgHasModule(organization, 'project_management');
  }
  return true;
}

List<OptionItem> structureNodeOptions(List<Map<String, dynamic>> nodes) {
  final byId = <String, Map<String, dynamic>>{};
  for (final node in nodes) {
    final id = idOf(node);
    if (id != null && id.isNotEmpty) byId[id] = node;
  }

  String labelFor(Map<String, dynamic> node) {
    final apiLabel = node['label']?.toString().trim() ?? '';
    if (apiLabel.isNotEmpty) return apiLabel;
    final names = <String>[];
    final seen = <String>{};
    Map<String, dynamic>? current = node;
    while (current != null) {
      final id = idOf(current);
      if (id == null || id.isEmpty || !seen.add(id)) break;
      final name = current['name']?.toString().trim() ?? '';
      names.insert(0, name.isEmpty ? 'Node' : name);
      final parentId = idOf(current['parent']);
      current = parentId == null ? null : byId[parentId];
    }
    final type = structureNodeTypeLabels[node['type']?.toString() ?? ''] ?? '';
    final path = names.join(' / ');
    if (type.isEmpty) return path;
    return '$path · $type';
  }

  final options = <OptionItem>[
    for (final node in nodes)
      if (idOf(node) != null && idOf(node)!.isNotEmpty)
        OptionItem(
          value: idOf(node)!,
          label: labelFor(node),
          raw: node,
        ),
  ];
  final keepApiOrder = nodes.isNotEmpty &&
      nodes.every((node) => (node['label']?.toString().trim() ?? '').isNotEmpty);
  if (!keepApiOrder) {
    options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
  return options;
}
