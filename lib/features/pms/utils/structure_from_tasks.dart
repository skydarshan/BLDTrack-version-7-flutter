import '../../../core/network/api_helpers.dart';

/// What task titles this build looks for. Parsing stays on the server.
const fromTasksHelp =
    'Task titles such as Tower A › Level 3 › Slab are read for buildings and floors. '
    'Missing buildings and floors are created, and each matching task is linked to its building or floor. '
    'Existing buildings are matched by name and existing floors by level. '
    'Tasks that already have a link are left unchanged.\n\n'
    'Recognised floors include Ground Floor, GF, Stilt, Level 3, L3, 3rd Floor, Basement 1, B1, Terrace, and Roof. '
    'Recognised buildings include Tower A, Block 2, Wing B, and Villa 4.';

/// One task the preview will link. Tasks that already have a link are not listed.
class FromTasksLink {
  const FromTasksLink({required this.id, required this.title});

  final String id;
  final String title;
}

/// A floor found in task titles. [exists] is an existing floor at this level.
class FromTasksFloorPlan {
  const FromTasksFloorPlan({
    required this.name,
    required this.levelNumber,
    required this.nodeId,
    required this.exists,
    required this.tasksToLink,
  });

  final String name;
  final int? levelNumber;
  final String? nodeId;
  final bool exists;
  final List<FromTasksLink> tasksToLink;
}

/// A building found in task titles. [exists] is a building with the same name.
class FromTasksBuildingPlan {
  const FromTasksBuildingPlan({
    required this.name,
    required this.nodeId,
    required this.exists,
    required this.tasksToLink,
    required this.floors,
  });

  final String name;
  final String? nodeId;
  final bool exists;
  final List<FromTasksLink> tasksToLink;
  final List<FromTasksFloorPlan> floors;
}

/// `POST /projects/:id/structure/from-tasks` with `preview: true`.
class FromTasksPlan {
  const FromTasksPlan({
    required this.buildingsNew,
    required this.floorsNew,
    required this.tasksToLink,
    required this.tasksAlreadyLinked,
    required this.warnings,
    required this.buildings,
  });

  final int buildingsNew;
  final int floorsNew;
  final int tasksToLink;
  final int tasksAlreadyLinked;
  final List<String> warnings;
  final List<FromTasksBuildingPlan> buildings;

  /// Commit only when something would be created or linked.
  bool get canCommit => buildingsNew > 0 || floorsNew > 0 || tasksToLink > 0;
}

bool fromTasksPreviewAccepted(Map<String, dynamic> data) {
  if (data['preview'] == false) return false;
  return data['preview'] == true || data.containsKey('buildings') || data.containsKey('counts');
}

FromTasksPlan? readFromTasksPlan(Map<String, dynamic> data) {
  if (!fromTasksPreviewAccepted(data)) return null;
  final counts = data['counts'] is Map
      ? Map<String, dynamic>.from(data['counts'] as Map)
      : const <String, dynamic>{};
  final buildings = _buildings(data['buildings']);
  final derivedBuildings = buildings.where((building) => !building.exists).length;
  final derivedFloors = buildings.fold<int>(
    0,
    (sum, building) => sum + building.floors.where((floor) => !floor.exists).length,
  );
  final derivedTasks = buildings.fold<int>(
    0,
    (sum, building) =>
        sum +
        building.tasksToLink.length +
        building.floors.fold<int>(0, (floorSum, floor) => floorSum + floor.tasksToLink.length),
  );
  return FromTasksPlan(
    buildingsNew: _count(counts, 'buildings_new', derivedBuildings),
    floorsNew: _count(counts, 'floors_new', derivedFloors),
    tasksToLink: _count(counts, 'tasks_to_link', derivedTasks),
    tasksAlreadyLinked: _count(counts, 'tasks_already_linked', 0),
    warnings: _warnings(data['warnings']),
    buildings: buildings,
  );
}

/// "1 new building, 1 new floor, 2 tasks to link".
String fromTasksSummary(FromTasksPlan plan) {
  final parts = <String>[];
  void add(int count, String singular, String plural) {
    if (count <= 0) return;
    parts.add('$count ${count == 1 ? singular : plural}');
  }

  add(plan.buildingsNew, 'new building', 'new buildings');
  add(plan.floorsNew, 'new floor', 'new floors');
  add(plan.tasksToLink, 'task to link', 'tasks to link');

  final already = plan.tasksAlreadyLinked;
  final alreadyText = already <= 0
      ? ''
      : '${already == 1 ? '1 task is' : '$already tasks are'} already linked';

  if (parts.isEmpty) {
    if (alreadyText.isEmpty) return 'Nothing new to add.';
    return '$alreadyText. Nothing new to add.';
  }
  if (alreadyText.isEmpty) return parts.join(', ');
  return '${parts.join(', ')}. $alreadyText';
}

String fromTasksResultMessage({required int createdNodes, required int linkedTasks}) {
  final nodes = createdNodes == 1 ? 'node' : 'nodes';
  final tasks = linkedTasks == 1 ? 'task' : 'tasks';
  return 'Added $createdNodes $nodes. Linked $linkedTasks $tasks.';
}

/// One place a task title names a building, and maybe a floor.
class ParsedStructureTitle {
  const ParsedStructureTitle({
    required this.buildingName,
    this.level,
    this.floorName,
    this.terrace = false,
  });

  final String buildingName;
  final int? level;
  final String? floorName;
  final bool terrace;

  bool get hasFloor => terrace || level != null;
}

/// Reads a title or a `›` path such as `Tower A › Level 3 › Slab`.
///
/// Floors: Ground Floor, GF, Stilt, Level 3, L3, 3rd Floor, Basement 1, B1,
/// Terrace, Roof. Buildings: Tower A, Block 2, Wing B, Villa 4.
ParsedStructureTitle? parseStructureTaskTitle(String title) {
  final parts = title
      .split(RegExp(r'\s*(?:›|>|/|\|)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  String? building;
  ParsedStructureTitle? floor;
  for (final part in parts) {
    final parsedBuilding = _buildingName(part);
    if (parsedBuilding != null && building == null) building = parsedBuilding;
    final parsedFloor = _floorPart(part);
    if (parsedFloor != null && floor == null) floor = parsedFloor;
  }
  if (building == null) return null;
  return ParsedStructureTitle(
    buildingName: building,
    level: floor?.level,
    floorName: floor?.floorName,
    terrace: floor?.terrace ?? false,
  );
}

/// Preview body for the from-tasks screen. Null when no building is found.
///
/// [tasks] may be a nested task tree. A task is read with its ancestor titles,
/// so `Tower A` → `Level 3` → `Slab` is the same as one title joined by `›`.
/// Existing buildings match by name. Existing floors match by level.
Map<String, dynamic>? planStructureFromTasks({
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> nodes,
}) {
  final flat = _flattenTasks(tasks);
  final hits = <_TaskHit>[];
  for (final task in flat) {
    final parsed = parseStructureTaskTitle(task.path);
    if (parsed == null) continue;
    hits.add(_TaskHit(task: task, parsed: parsed));
  }
  if (hits.isEmpty) return null;

  final buildings = <String, _BuildingBucket>{};
  for (final hit in hits) {
    final key = hit.parsed.buildingName.toLowerCase();
    buildings.putIfAbsent(key, () => _BuildingBucket(hit.parsed.buildingName)).hits.add(hit);
  }

  final buildingNodes = <Map<String, dynamic>>[];
  var buildingsNew = 0;
  var floorsNew = 0;
  var tasksToLink = 0;
  var tasksAlreadyLinked = 0;

  for (final bucket in buildings.values) {
    final existingBuilding = _findBuilding(nodes, bucket.name);
    final buildingId = idOf(existingBuilding);
    final buildingName = existingBuilding?['name']?.toString().trim().isNotEmpty == true
        ? existingBuilding!['name'].toString().trim()
        : bucket.name;
    if (existingBuilding == null) buildingsNew += 1;

    final floors = <String, _FloorBucket>{};
    final buildingTasks = <Map<String, dynamic>>[];
    for (final hit in bucket.hits) {
      if (_taskHasLinks(hit.task.raw)) {
        tasksAlreadyLinked += 1;
        continue;
      }
      if (!hit.parsed.hasFloor) {
        buildingTasks.add({
          '_id': hit.task.id,
          'title': hit.task.title,
        });
        tasksToLink += 1;
        continue;
      }
      final floorKey = hit.parsed.terrace ? 'terrace' : 'level:${hit.parsed.level}';
      floors
          .putIfAbsent(
            floorKey,
            () => _FloorBucket(
              name: hit.parsed.floorName ?? 'Floor',
              level: hit.parsed.level,
              terrace: hit.parsed.terrace,
            ),
          )
          .tasks
          .add({
            '_id': hit.task.id,
            'title': hit.task.title,
          });
      tasksToLink += 1;
    }

    final numericLevels = <int>[
      for (final floor in floors.values)
        if (!floor.terrace && floor.level != null) floor.level!,
      for (final node in nodes)
        if (node['type'] == 'floor' &&
            idOf(node['parent']) == buildingId &&
            asNum(node['level_number']) != null)
          asNum(node['level_number'])!.toInt(),
    ];
    if (floors.containsKey('terrace')) {
      final top = numericLevels.isEmpty ? 0 : numericLevels.reduce((a, b) => a > b ? a : b);
      floors['terrace']!.level = top + 1;
      floors['terrace']!.name = 'Terrace';
    }

    if (buildingTasks.isEmpty && floors.isEmpty && existingBuilding == null) {
      buildingsNew -= 1;
      continue;
    }

    final floorNodes = <Map<String, dynamic>>[];
    final ordered = floors.values.toList()
      ..sort((a, b) => (a.level ?? 0).compareTo(b.level ?? 0));
    for (final floor in ordered) {
      final existingFloor = buildingId == null
          ? null
          : _findFloor(nodes, buildingId, floor.level);
      if (existingFloor == null) floorsNew += 1;
      final existingName = existingFloor?['name']?.toString().trim() ?? '';
      floorNodes.add({
        'name': existingName.isNotEmpty ? existingName : floor.name,
        'level_number': floor.level,
        'node_id': idOf(existingFloor),
        'exists': existingFloor != null,
        'tasks_to_link': floor.tasks,
      });
    }

    buildingNodes.add({
      'name': buildingName,
      'node_id': buildingId,
      'exists': existingBuilding != null,
      'tasks_to_link': buildingTasks,
      'floors': floorNodes,
    });
  }

  return {
    'preview': true,
    'counts': {
      'buildings_new': buildingsNew,
      'floors_new': floorsNew,
      'tasks_to_link': tasksToLink,
      'tasks_already_linked': tasksAlreadyLinked,
    },
    'warnings': <String>[],
    'buildings': buildingNodes,
  };
}

/// Creates missing buildings and floors, then links each matching task.
Future<Map<String, dynamic>> commitPlannedStructureFromTasks({
  required Map<String, dynamic> preview,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> body) createNode,
  required Future<void> Function(String taskId, String nodeId) linkTask,
}) async {
  final plan = readFromTasksPlan(preview);
  if (plan == null || !plan.canCommit) {
    return {
      'preview': false,
      'created_nodes': 0,
      'linked_tasks': 0,
    };
  }
  var created = 0;
  var linked = 0;
  for (final building in plan.buildings) {
    var buildingId = building.nodeId;
    if (buildingId == null || buildingId.isEmpty) {
      final node = await createNode({
        'type': 'building',
        'name': building.name,
      });
      buildingId = idOf(node);
      created += 1;
    }
    if (buildingId == null || buildingId.isEmpty) continue;
    for (final task in building.tasksToLink) {
      if (task.id.isEmpty) continue;
      await linkTask(task.id, buildingId);
      linked += 1;
    }
    for (final floor in building.floors) {
      var floorId = floor.nodeId;
      if (floorId == null || floorId.isEmpty) {
        final node = await createNode({
          'type': 'floor',
          'parent': buildingId,
          'name': floor.name,
          if (floor.levelNumber != null) 'level_number': floor.levelNumber,
          if (floor.levelNumber != null && floor.levelNumber! < 0) 'category': 'Basement',
        });
        floorId = idOf(node);
        created += 1;
      }
      if (floorId == null || floorId.isEmpty) continue;
      for (final task in floor.tasksToLink) {
        if (task.id.isEmpty) continue;
        await linkTask(task.id, floorId);
        linked += 1;
      }
    }
  }
  return {
    'preview': false,
    'counts': {
      'buildings_new': plan.buildingsNew,
      'floors_new': plan.floorsNew,
      'tasks_to_link': plan.tasksToLink,
      'tasks_already_linked': plan.tasksAlreadyLinked,
    },
    'created_nodes': created,
    'linked_tasks': linked,
  };
}

String fromTasksFloorSubtitle(FromTasksFloorPlan floor) {
  final parts = <String>['Floor'];
  if (floor.levelNumber != null) parts.add('level ${floor.levelNumber}');
  parts.add(floor.exists ? 'Existing' : 'New');
  return parts.join(' · ');
}

int _count(Map<String, dynamic> counts, String key, int fallback) {
  if (!counts.containsKey(key)) return fallback;
  return asNum(counts[key])?.toInt() ?? fallback;
}

List<String> _warnings(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is String) {
      final text = item.trim();
      if (text.isNotEmpty) out.add(text);
    } else if (item is Map) {
      final text = (item['message'] ?? item['warning'])?.toString().trim() ?? '';
      if (text.isNotEmpty) out.add(text);
    }
  }
  return out;
}

List<FromTasksBuildingPlan> _buildings(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) _building(Map<String, dynamic>.from(item)),
  ];
}

FromTasksBuildingPlan _building(Map<String, dynamic> raw) {
  final floorsRaw = raw['floors'];
  final floors = floorsRaw is List
      ? [
          for (final item in floorsRaw)
            if (item is Map) _floor(Map<String, dynamic>.from(item)),
        ]
      : const <FromTasksFloorPlan>[];
  return FromTasksBuildingPlan(
    name: raw['name']?.toString().trim() ?? '',
    nodeId: _nodeId(raw['node_id']),
    exists: _exists(raw),
    tasksToLink: _tasks(raw['tasks_to_link']),
    floors: floors,
  );
}

FromTasksFloorPlan _floor(Map<String, dynamic> raw) {
  final level = asNum(raw['level_number']);
  return FromTasksFloorPlan(
    name: raw['name']?.toString().trim() ?? '',
    levelNumber: level?.toInt(),
    nodeId: _nodeId(raw['node_id']),
    exists: _exists(raw),
    tasksToLink: _tasks(raw['tasks_to_link']),
  );
}

List<FromTasksLink> _tasks(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        FromTasksLink(
          id: (item['_id'] ?? item['id'])?.toString() ?? '',
          title: item['title']?.toString().trim() ?? '',
        ),
  ];
}

class _FlatTask {
  const _FlatTask({required this.id, required this.title, required this.path, required this.raw});

  final String id;
  final String title;
  final String path;
  final Map<String, dynamic> raw;
}

class _TaskHit {
  const _TaskHit({required this.task, required this.parsed});

  final _FlatTask task;
  final ParsedStructureTitle parsed;
}

class _BuildingBucket {
  _BuildingBucket(this.name);

  final String name;
  final hits = <_TaskHit>[];
}

class _FloorBucket {
  _FloorBucket({required this.name, required this.level, required this.terrace});

  String name;
  int? level;
  final bool terrace;
  final tasks = <Map<String, dynamic>>[];
}

List<_FlatTask> _flattenTasks(List<Map<String, dynamic>> roots) {
  final out = <_FlatTask>[];
  void walk(Map<String, dynamic> node, List<String> ancestors) {
    final title = node['title']?.toString().trim() ?? '';
    final path = [
      ...ancestors,
      if (title.isNotEmpty) title,
    ];
    out.add(
      _FlatTask(
        id: (node['_id'] ?? node['id'])?.toString() ?? '',
        title: title,
        path: path.join(' › '),
        raw: node,
      ),
    );
    final children = node['children'];
    if (children is! List) return;
    for (final child in children) {
      if (child is Map) walk(Map<String, dynamic>.from(child), path);
    }
  }

  for (final root in roots) {
    walk(root, const []);
  }
  return out;
}

String? _buildingName(String text) {
  final match = RegExp(
    r'^(tower|block|wing|villa)\s+([a-z0-9-]+)$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final kind = match.group(1)!;
  final label = kind[0].toUpperCase() + kind.substring(1).toLowerCase();
  return '$label ${match.group(2)!.toUpperCase()}';
}

ParsedStructureTitle? _floorPart(String text) {
  final compact = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(r'^(ground\s*floor|gf|stilt)$', caseSensitive: false).hasMatch(compact)) {
    return const ParsedStructureTitle(buildingName: '', level: 0, floorName: 'Ground Floor');
  }
  if (RegExp(r'^(terrace|roof)$', caseSensitive: false).hasMatch(compact)) {
    return const ParsedStructureTitle(buildingName: '', terrace: true, floorName: 'Terrace');
  }
  final basement = RegExp(r'^(?:basement\s*(\d+)|b(\d+))$', caseSensitive: false).firstMatch(compact);
  if (basement != null) {
    final number = int.parse(basement.group(1) ?? basement.group(2)!);
    return ParsedStructureTitle(
      buildingName: '',
      level: -number,
      floorName: 'Basement $number',
    );
  }
  final numbered = RegExp(
    r'^(?:(?:level|floor|l)\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+floor)$',
    caseSensitive: false,
  ).firstMatch(compact);
  if (numbered != null) {
    final number = int.parse(numbered.group(1) ?? numbered.group(2)!);
    return ParsedStructureTitle(
      buildingName: '',
      level: number,
      floorName: number == 0 ? 'Ground Floor' : 'Floor $number',
    );
  }
  return null;
}

bool _taskHasLinks(Map<String, dynamic> task) {
  final links = task['structure_nodes'];
  return links is List && links.isNotEmpty;
}

Map<String, dynamic>? _findBuilding(List<Map<String, dynamic>> nodes, String name) {
  final key = name.trim().toLowerCase();
  for (final node in nodes) {
    if (node['type'] != 'building') continue;
    if ((node['name']?.toString().trim().toLowerCase() ?? '') == key) return node;
  }
  return null;
}

Map<String, dynamic>? _findFloor(
  List<Map<String, dynamic>> nodes,
  String buildingId,
  int? level,
) {
  if (level == null) return null;
  for (final node in nodes) {
    if (node['type'] != 'floor') continue;
    if (idOf(node['parent']) != buildingId) continue;
    if (asNum(node['level_number'])?.toInt() == level) return node;
  }
  return null;
}

bool _exists(Map<String, dynamic> node) {
  if (node['exists'] is bool) return node['exists'] as bool;
  return _nodeId(node['node_id']) != null;
}

String? _nodeId(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}
