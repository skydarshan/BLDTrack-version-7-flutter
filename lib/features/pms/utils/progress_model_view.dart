import '../../../core/network/api_helpers.dart';

/// One structure node in the project tree.
class StackedCell {
  const StackedCell({
    required this.nodeId,
    required this.name,
    required this.type,
    this.code,
    this.category,
    this.levelNumber,
    this.fromLevel,
    this.toLevel,
  });

  final String nodeId;
  final String name;
  final String type;
  final String? code;
  final String? category;
  final num? levelNumber;
  final num? fromLevel;
  final num? toLevel;
}

class StackedFloor {
  const StackedFloor({
    required this.node,
    required this.children,
  });

  final StackedCell node;
  final List<StackedCell> children;
}

class StackedBuilding {
  const StackedBuilding({
    required this.node,
    required this.floors,
    required this.cores,
  });

  final StackedCell node;
  final List<StackedFloor> floors;
  final List<StackedCell> cores;
}

class StackedModel {
  const StackedModel({
    required this.buildings,
    required this.externalAreas,
  });

  final List<StackedBuilding> buildings;
  final List<StackedCell> externalAreas;
}

Map<String, Map<String, dynamic>> indexProgressNodes(dynamic nodes) {
  final out = <String, Map<String, dynamic>>{};
  if (nodes is! List) return out;
  for (final raw in nodes) {
    if (raw is! Map) continue;
    final node = Map<String, dynamic>.from(raw);
    final id = node['node_id']?.toString();
    if (id == null || id.isEmpty) continue;
    out[id] = node;
  }
  return out;
}

List<Map<String, dynamic>> legendItems(dynamic legend) {
  if (legend is! List) return const [];
  return legend
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String legendLabel(List<Map<String, dynamic>> legend, String? key) {
  if (key == null || key.isEmpty) return '';
  for (final item in legend) {
    if (item['key']?.toString() == key) {
      final label = item['label']?.toString().trim() ?? '';
      if (label.isNotEmpty) return label;
    }
  }
  return key;
}

String? legendColor(List<Map<String, dynamic>> legend, String key) {
  for (final item in legend) {
    if (item['key']?.toString() == key) {
      final color = item['color']?.toString().trim() ?? '';
      if (color.isNotEmpty) return color;
    }
  }
  return null;
}

/// Parses `#RRGGBB` / `#AARRGGBB` into an ARGB int. Returns null when invalid.
int? colorValueFromHex(String? raw) {
  if (raw == null) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

String formatProgressPercent(dynamic value) {
  final n = asNum(value);
  if (n == null) return '—';
  if (n == n.roundToDouble()) return '${n.toInt()}%';
  return '${n.toStringAsFixed(1)}%';
}

String formatLevel(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// Labels from the structure mental model.
String structureTypeLabel(String type) {
  switch (type) {
    case 'building':
      return 'Building';
    case 'external_area':
      return 'External area';
    case 'floor':
      return 'Floor';
    case 'core':
      return 'Core';
    case 'unit':
      return 'Unit';
    case 'common_area':
      return 'Common area';
    default:
      return type;
  }
}

/// Type, level, code and category. Does not build a path label.
String structureNodeDetail(StackedCell cell) {
  final parts = <String>[structureTypeLabel(cell.type)];
  if (cell.type == 'floor' && cell.levelNumber != null) {
    parts.add('level ${formatLevel(cell.levelNumber!)}');
  }
  if (cell.type == 'core' && cell.fromLevel != null && cell.toLevel != null) {
    parts.add('levels ${formatLevel(cell.fromLevel!)} → ${formatLevel(cell.toLevel!)}');
  }
  if (cell.code != null) parts.add('code ${cell.code}');
  if (cell.category != null) parts.add(cell.category!);
  return parts.join(' · ');
}

/// Core link "{ node, floor_level }" shown as "at level N".
List<String> coreFloorLevelNotes(Map<String, dynamic> task) {
  final links = task['structure_nodes'];
  if (links is! List) return const [];
  final notes = <String>[];
  for (final link in links) {
    if (link is! Map) continue;
    final level = asNum(link['floor_level']);
    if (level == null) continue;
    notes.add('at level ${formatLevel(level)}');
  }
  return notes;
}

Set<String> geometryNodeIds(Map<String, dynamic>? model) {
  final ids = <String>{};
  if (model == null) return ids;
  void add(dynamic node) {
    if (node is! Map) return;
    final id = node['node_id']?.toString();
    if (id != null && id.isNotEmpty) ids.add(id);
  }

  final buildings = model['buildings'];
  if (buildings is List) {
    for (final building in buildings) {
      if (building is! Map) continue;
      add(building);
      final floors = building['floors'];
      if (floors is List) {
        for (final floor in floors) {
          if (floor is! Map) continue;
          add(floor);
          for (final key in ['units', 'common_areas']) {
            final parts = floor[key];
            if (parts is! List) continue;
            for (final part in parts) {
              add(part);
            }
          }
        }
      }
      final cores = building['cores'];
      if (cores is List) {
        for (final core in cores) {
          add(core);
        }
      }
    }
  }
  final external = model['external_areas'];
  if (external is List) {
    for (final area in external) {
      add(area);
    }
  }
  return ids;
}

/// True when every progress node is present in the cached geometry.
bool modelCoversProgressNodes(
  Map<String, dynamic>? model,
  Iterable<String> nodeIds,
) {
  if (model == null) return false;
  final have = geometryNodeIds(model);
  for (final id in nodeIds) {
    if (!have.contains(id)) return false;
  }
  return true;
}

String? _optionalText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

StackedCell? _cellOf(dynamic raw) {
  if (raw is! Map) return null;
  final id = raw['node_id']?.toString() ?? '';
  if (id.isEmpty) return null;
  final name = raw['name']?.toString().trim() ?? '';
  return StackedCell(
    nodeId: id,
    name: name.isEmpty ? id : name,
    type: raw['type']?.toString() ?? '',
    code: _optionalText(raw['code']),
    category: _optionalText(raw['category']),
    levelNumber: asNum(raw['level_number']),
    fromLevel: asNum(raw['from_level']),
    toLevel: asNum(raw['to_level']),
  );
}

/// Buildings, then their floors by level_number (low to high), then cores.
/// Units and common areas stay under their floor. External areas stay top-level.
StackedModel stackedModelFromGeometry(Map<String, dynamic>? model) {
  if (model == null) {
    return const StackedModel(buildings: [], externalAreas: []);
  }
  final buildings = <StackedBuilding>[];
  final rawBuildings = model['buildings'];
  if (rawBuildings is List) {
    for (final raw in rawBuildings) {
      if (raw is! Map) continue;
      final building = _cellOf(raw);
      if (building == null) continue;
      final floors = <StackedFloor>[];
      final rawFloors = raw['floors'];
      if (rawFloors is List) {
        final sorted = rawFloors.whereType<Map>().toList()
          ..sort((a, b) {
            final left = asNum(a['level_number']) ?? 0;
            final right = asNum(b['level_number']) ?? 0;
            return left.compareTo(right);
          });
        for (final floor in sorted) {
          final floorCell = _cellOf(floor);
          if (floorCell == null) continue;
          final children = <StackedCell>[];
          for (final key in ['units', 'common_areas']) {
            final list = floor[key];
            if (list is! List) continue;
            for (final part in list) {
              final cell = _cellOf(part);
              if (cell != null) children.add(cell);
            }
          }
          floors.add(StackedFloor(node: floorCell, children: children));
        }
      }
      final cores = <StackedCell>[];
      final rawCores = raw['cores'];
      if (rawCores is List) {
        for (final core in rawCores) {
          final cell = _cellOf(core);
          if (cell != null) cores.add(cell);
        }
      }
      buildings.add(
        StackedBuilding(
          node: building,
          floors: floors,
          cores: cores,
        ),
      );
    }
  }
  final external = <StackedCell>[];
  final rawExternal = model['external_areas'];
  if (rawExternal is List) {
    for (final area in rawExternal) {
      final cell = _cellOf(area);
      if (cell != null) external.add(cell);
    }
  }
  return StackedModel(buildings: buildings, externalAreas: external);
}

List<Map<String, dynamic>> assignedMembersOf(Map<String, dynamic> task) {
  final raw = task['assignedMembers'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

String taskPathLabel(dynamic path) {
  if (path is! List || path.isEmpty) return '';
  return path.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).join(' › ');
}

bool taskInheritsStructureLink(Map<String, dynamic> task) {
  final links = task['structure_nodes'];
  return links is List && links.isEmpty;
}
