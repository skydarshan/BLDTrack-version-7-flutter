import '../../../core/network/api_helpers.dart';
import 'structure_access.dart';

/// Building and external area are the only types with no parent.
bool structureTypeAllowsParent(String type) =>
    type != 'building' && type != 'external_area';

/// A sensible type when adding a child under [parentType].
String structureChildType(String? parentType) {
  switch (parentType) {
    case 'building':
      return 'floor';
    case 'floor':
      return 'unit';
    case null:
    case '':
      return 'building';
    default:
      return 'common_area';
  }
}

int structureTaskCount(Map<String, dynamic> node) {
  final count = asNum(node['task_count']);
  if (count == null || count <= 0) return 0;
  return count.toInt();
}

String structureDeleteMessage(Map<String, dynamic> node) {
  final name = node['name']?.toString().trim() ?? '';
  final label = name.isEmpty ? 'This node' : name;
  final tasks = structureTaskCount(node);
  if (tasks == 0) return label;
  final noun = tasks == 1 ? 'task is' : 'tasks are';
  return '$label\n\n$tasks $noun linked directly to this node. Tasks are not deleted.';
}

List<Map<String, dynamic>> structureChildNodes(Map<String, dynamic> node) {
  final raw = node['children'];
  if (raw is! List) return const [];
  return [
    for (final child in raw)
      if (child is Map<String, dynamic>)
        child
      else if (child is Map)
        Map<String, dynamic>.from(child),
  ];
}

/// Tree response (`tree`) or a flat `nodes` list, as nested roots.
///
/// An empty project is `tree: []` or `nodes: []`. That is an empty list.
List<Map<String, dynamic>> structureTreeRoots(Map<String, dynamic> data) {
  final tree = data['tree'];
  if (tree is List) return _copyNodes(tree);
  final nodes = data['nodes'];
  if (nodes is List) {
    return nestStructureNodes([
      for (final raw in nodes)
        if (raw is Map) Map<String, dynamic>.from(raw),
    ]);
  }
  return const [];
}

/// Flat picker list (`?flat=true`). Display order is kept.
List<Map<String, dynamic>> readStructureNodeList(Map<String, dynamic> data) {
  final nodes = data['nodes'];
  if (nodes is! List) return const [];
  return [
    for (final raw in nodes)
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
}

/// Resolve results grouped by parent id. A missing parent uses `''`.
Map<String, List<Map<String, dynamic>>> groupStructureNodesByParent(
  List<Map<String, dynamic>> nodes,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final node in nodes) {
    final parent = idOf(node['parent']) ?? '';
    groups.putIfAbsent(parent, () => []).add(node);
  }
  return groups;
}

List<Map<String, dynamic>> flattenStructureNodes(List<Map<String, dynamic>> roots) {
  final out = <Map<String, dynamic>>[];
  void walk(List<Map<String, dynamic>> nodes) {
    for (final node in nodes) {
      out.add(node);
      walk(structureChildNodes(node));
    }
  }

  walk(roots);
  return out;
}

Set<String> structureDescendantIds(String nodeId, List<Map<String, dynamic>> nodes) {
  final byParent = <String, List<String>>{};
  for (final node in nodes) {
    final id = idOf(node);
    final parent = idOf(node['parent']);
    if (id == null || id.isEmpty || parent == null || parent.isEmpty) continue;
    byParent.putIfAbsent(parent, () => []).add(id);
  }
  final out = <String>{};
  void walk(String current) {
    for (final child in byParent[current] ?? const <String>[]) {
      if (out.add(child)) walk(child);
    }
  }

  walk(nodeId);
  return out;
}

List<Map<String, dynamic>> nestStructureNodes(List<Map<String, dynamic>> nodes) {
  final copies = <Map<String, dynamic>>[];
  final byParent = <String?, List<Map<String, dynamic>>>{};
  for (final node in nodes) {
    final copy = Map<String, dynamic>.from(node);
    copy['children'] = <Map<String, dynamic>>[];
    copies.add(copy);
    byParent.putIfAbsent(idOf(copy['parent']), () => []).add(copy);
  }
  final known = <String>{
    for (final node in copies)
      if (idOf(node) != null) idOf(node)!,
  };
  void attach(Map<String, dynamic> node) {
    final children = byParent[idOf(node)] ?? const <Map<String, dynamic>>[];
    node['children'] = children;
    for (final child in children) {
      attach(child);
    }
  }

  final roots = <Map<String, dynamic>>[
    ...?byParent[null],
    for (final node in copies)
      if (!known.contains(idOf(node['parent']))) node,
  ];
  final seen = <String>{};
  final uniqueRoots = <Map<String, dynamic>>[];
  for (final root in roots) {
    final id = idOf(root) ?? '';
    if (id.isNotEmpty && !seen.add(id)) continue;
    uniqueRoots.add(root);
    attach(root);
  }
  return uniqueRoots;
}

List<Map<String, dynamic>> reorderStructureSiblings(
  List<Map<String, dynamic>> roots,
  String? parentId,
  List<String> nodeIds,
) {
  List<Map<String, dynamic>> sort(List<Map<String, dynamic>> nodes) {
    final byId = <String, Map<String, dynamic>>{};
    for (final node in nodes) {
      final id = idOf(node);
      if (id != null) byId[id] = node;
    }
    final ordered = <Map<String, dynamic>>[];
    final used = <String>{};
    for (final id in nodeIds) {
      final node = byId[id];
      if (node != null && used.add(id)) ordered.add(node);
    }
    for (final node in nodes) {
      final id = idOf(node);
      if (id == null || used.add(id)) ordered.add(node);
    }
    return ordered;
  }

  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> nodes, String? owner) {
    final current = owner == parentId ? sort(nodes) : nodes;
    return [
      for (final node in current)
        () {
          final copy = Map<String, dynamic>.from(node);
          copy['children'] = apply(structureChildNodes(node), idOf(node));
          return copy;
        }(),
    ];
  }

  return apply(roots, null);
}

/// Create or patch body. [payload] is null when [errors] must be shown.
/// An empty payload means nothing changed.
class StructureWrite {
  const StructureWrite.ok(this.payload) : errors = const {};

  const StructureWrite.invalid(this.errors) : payload = null;

  final Map<String, dynamic>? payload;
  final Map<String, String> errors;

  bool get isValid => payload != null;
}

StructureWrite structureCreateBody({
  required String type,
  required String? parentId,
  required String? parentType,
  required String name,
  required String code,
  required String category,
  required String levelText,
  required String fromLevelText,
  required String toLevelText,
  Map<String, String> geometryText = const {},
}) {
  final errors = <String, String>{};
  if (!structureNodeTypeLabels.containsKey(type)) {
    errors['type'] = 'Type is required';
  }
  final parent = _cleanId(parentId);
  if (structureTypeAllowsParent(type)) {
    if (parent == null) errors['parent'] = 'Parent is required';
    if (type == 'unit' && parent != null && parentType != 'floor') {
      errors['parent'] = 'A unit must be placed under a floor';
    }
  }
  final trimmedName = name.trim();
  if (type != 'floor' && trimmedName.isEmpty) {
    errors['name'] = 'Name is required';
  }
  final level = _parseWhole(
    levelText,
    label: 'Level',
    required: type == 'floor',
  );
  final fromLevel = _parseWhole(
    fromLevelText,
    label: 'From level',
    required: type == 'core',
  );
  final toLevel = _parseWhole(
    toLevelText,
    label: 'To level',
    required: type == 'core',
  );
  if (type == 'floor' && level.error != null) errors['level_number'] = level.error!;
  if (type == 'core' && fromLevel.error != null) errors['from_level'] = fromLevel.error!;
  if (type == 'core' && toLevel.error != null) errors['to_level'] = toLevel.error!;
  if (type == 'core' &&
      fromLevel.value != null &&
      toLevel.value != null &&
      fromLevel.value! > toLevel.value!) {
    errors['from_level'] = 'From level cannot be above to level';
    errors['to_level'] = 'From level cannot be above to level';
  }
  if (errors.isNotEmpty) return StructureWrite.invalid(errors);

  final payload = <String, dynamic>{'type': type};
  if (structureTypeAllowsParent(type)) payload['parent'] = parent;
  if (trimmedName.isNotEmpty) payload['name'] = trimmedName;
  final trimmedCode = code.trim();
  if (trimmedCode.isNotEmpty) payload['code'] = trimmedCode;
  final trimmedCategory = category.trim();
  if (trimmedCategory.isNotEmpty) payload['category'] = trimmedCategory;
  if (type == 'floor') payload['level_number'] = level.value;
  if (type == 'core') {
    payload['from_level'] = fromLevel.value;
    payload['to_level'] = toLevel.value;
  }
  final geometry = _geometryPayload(geometryText, errors);
  if (errors.isNotEmpty) return StructureWrite.invalid(errors);
  if (geometry.isNotEmpty) payload['geometry'] = geometry;
  return StructureWrite.ok(payload);
}

StructureWrite structurePatchBody({
  required Map<String, dynamic> existing,
  required String? parentId,
  required String? parentType,
  required String name,
  required String code,
  required String category,
  required String levelText,
  required String fromLevelText,
  required String toLevelText,
  required Set<String> blockedParentIds,
  Map<String, String> geometryText = const {},
}) {
  final type = existing['type']?.toString() ?? '';
  final errors = <String, String>{};
  final parent = structureTypeAllowsParent(type) ? _cleanId(parentId) : null;
  if (structureTypeAllowsParent(type)) {
    if (parent == null) errors['parent'] = 'Parent is required';
    if (parent != null && blockedParentIds.contains(parent)) {
      errors['parent'] = 'A node cannot be moved under itself or one of its children';
    }
    if (type == 'unit' && parent != null && parentType != 'floor' && !errors.containsKey('parent')) {
      errors['parent'] = 'A unit must be placed under a floor';
    }
  }
  final trimmedName = name.trim();
  if (type != 'floor' && trimmedName.isEmpty) {
    errors['name'] = 'Name is required';
  }
  final level = _parseWhole(levelText, label: 'Level', required: type == 'floor');
  final fromLevel = _parseWhole(fromLevelText, label: 'From level', required: type == 'core');
  final toLevel = _parseWhole(toLevelText, label: 'To level', required: type == 'core');
  if (type == 'floor' && level.error != null) errors['level_number'] = level.error!;
  if (type == 'core' && fromLevel.error != null) errors['from_level'] = fromLevel.error!;
  if (type == 'core' && toLevel.error != null) errors['to_level'] = toLevel.error!;
  if (type == 'core' &&
      fromLevel.value != null &&
      toLevel.value != null &&
      fromLevel.value! > toLevel.value!) {
    errors['from_level'] = 'From level cannot be above to level';
    errors['to_level'] = 'From level cannot be above to level';
  }
  if (errors.isNotEmpty) return StructureWrite.invalid(errors);

  final payload = <String, dynamic>{};
  final existingName = existing['name']?.toString().trim() ?? '';
  if (trimmedName.isNotEmpty && trimmedName != existingName) payload['name'] = trimmedName;
  final trimmedCode = code.trim();
  final existingCode = existing['code']?.toString().trim() ?? '';
  if (trimmedCode != existingCode) payload['code'] = trimmedCode;
  final trimmedCategory = category.trim();
  final existingCategory = existing['category']?.toString().trim() ?? '';
  if (trimmedCategory != existingCategory) payload['category'] = trimmedCategory;
  if (structureTypeAllowsParent(type) && parent != idOf(existing['parent'])) {
    payload['parent'] = parent;
  }
  if (type == 'floor' && level.value != _whole(existing['level_number'])) {
    payload['level_number'] = level.value;
  }
  if (type == 'core' && fromLevel.value != _whole(existing['from_level'])) {
    payload['from_level'] = fromLevel.value;
  }
  if (type == 'core' && toLevel.value != _whole(existing['to_level'])) {
    payload['to_level'] = toLevel.value;
  }
  final existingGeometry = existing['geometry'] is Map
      ? Map<String, dynamic>.from(existing['geometry'] as Map)
      : const <String, dynamic>{};
  final geometry = _geometryPayload(geometryText, errors, existing: existingGeometry);
  if (errors.isNotEmpty) return StructureWrite.invalid(errors);
  if (geometry.isNotEmpty) payload['geometry'] = geometry;
  return StructureWrite.ok(payload);
}

String? _cleanId(String? id) {
  final text = id?.trim() ?? '';
  if (text.isEmpty) return null;
  return text;
}

int? _whole(dynamic value) {
  final number = asNum(value);
  if (number == null || number != number.roundToDouble()) return null;
  return number.toInt();
}

class _ParsedWhole {
  const _ParsedWhole.ok(this.value) : error = null;
  const _ParsedWhole.bad(this.error) : value = null;

  final int? value;
  final String? error;
}

_ParsedWhole _parseWhole(String text, {required String label, required bool required}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    if (required) return _ParsedWhole.bad('$label is required');
    return const _ParsedWhole.ok(null);
  }
  final value = int.tryParse(trimmed);
  if (value == null) return _ParsedWhole.bad('$label must be a whole number');
  return _ParsedWhole.ok(value);
}

List<Map<String, dynamic>> _copyNodes(List<dynamic> raw) {
  return [
    for (final item in raw)
      if (item is Map) _copyNode(Map<String, dynamic>.from(item)),
  ];
}

Map<String, dynamic> _copyNode(Map<String, dynamic> raw) {
  final node = Map<String, dynamic>.from(raw);
  node['children'] = _copyNodes(raw['children'] is List ? raw['children'] as List : const []);
  return node;
}

const _geometryLimits = <String, (num, num)>{
  'height': (0.5, 50),
  'width': (1, 1000),
  'depth': (1, 1000),
  'rotation': (-360, 360),
};

Map<String, num> _geometryPayload(
  Map<String, String> texts,
  Map<String, String> errors, {
  Map<String, dynamic>? existing,
}) {
  final out = <String, num>{};
  for (final entry in texts.entries) {
    final text = entry.value.trim();
    if (text.isEmpty) continue;
    final value = num.tryParse(text);
    final label = entry.key;
    if (value == null) {
      errors['geometry.$label'] = '$label must be a number';
      continue;
    }
    final limits = _geometryLimits[label];
    if (limits != null && (value < limits.$1 || value > limits.$2)) {
      errors['geometry.$label'] = '$label must be between ${limits.$1} and ${limits.$2}';
      continue;
    }
    if (existing != null && asNum(existing[label]) == value) continue;
    out[label] = value;
  }
  return out;
}
