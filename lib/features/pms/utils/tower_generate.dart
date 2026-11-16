import 'dart:convert';

import '../../../core/network/api_helpers.dart';
import 'structure_access.dart';
import 'structure_nodes.dart';

/// Default unit code pattern: floor 5, unit 3, tower A → `503A`.
const towerCodePatternDefault = '{floor}{unit:02}{tower}';

const towerClashHint =
    'Change the building name, building code, or code pattern, then preview again.';

/// One `{ field, value, message }` clash from a generate preview or a 409.
class TowerClash {
  const TowerClash({required this.field, required this.value, required this.message});

  final String field;
  final String value;
  final String message;
}

/// Body for `POST /projects/:id/structure/generate`, without the `preview` flag.
StructureWrite towerGenerateBody({
  required String name,
  required String code,
  required String basementsText,
  required bool groundFloor,
  required String floorsText,
  required bool terrace,
  required String unitsText,
  required String unitFromText,
  required String unitToText,
  required String unitCategory,
  required String codePattern,
  required String commonAreasText,
  required String liftsText,
  required String staircasesText,
  required String floorHeightText,
  required String widthText,
  required String depthText,
}) {
  final errors = <String, String>{};
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) errors['name'] = 'Building name is required';

  final trimmedCode = code.trim();
  if (trimmedCode.length > 20) {
    errors['code'] = 'Code must be 20 characters or less';
  }

  final basements = _count(basementsText, label: 'Basements', max: 10);
  final floors = _count(floorsText, label: 'Floors', max: 200);
  final units = _count(unitsText, label: 'Units per floor', max: 60);
  final lifts = _count(liftsText, label: 'Lifts', max: 100);
  final staircases = _count(staircasesText, label: 'Staircases', max: 100);
  if (basements.error != null) errors['basements'] = basements.error!;
  if (floors.error != null) errors['floors'] = floors.error!;
  if (units.error != null) errors['units_per_floor'] = units.error!;
  if (lifts.error != null) errors['lifts'] = lifts.error!;
  if (staircases.error != null) errors['staircases'] = staircases.error!;

  int? unitFrom;
  int? unitTo;
  if (units.value != null && units.value! > 0) {
    final from = _whole(unitFromText, label: 'Unit from level', required: true);
    final to = _whole(unitToText, label: 'Unit to level', required: true);
    if (from.error != null) errors['unit_from'] = from.error!;
    if (to.error != null) errors['unit_to'] = to.error!;
    if (from.value != null && to.value != null && from.value! > to.value!) {
      errors['unit_from'] = 'From level cannot be above to level';
      errors['unit_to'] = 'From level cannot be above to level';
    }
    unitFrom = from.value;
    unitTo = to.value;
  }

  final areas = parseCommonAreaNames(commonAreasText);
  if (areas.length > 20) {
    errors['common_areas'] = 'Common areas cannot be more than 20';
  }

  final height = _optionalSize(
    floorHeightText,
    label: 'Floor height',
    min: 0.5,
    max: 50,
  );
  final width = _optionalSize(widthText, label: 'Width', min: 1, max: 1000);
  final depth = _optionalSize(depthText, label: 'Depth', min: 1, max: 1000);
  if (height.error != null) errors['floor_height'] = height.error!;
  if (width.error != null) errors['width'] = width.error!;
  if (depth.error != null) errors['depth'] = depth.error!;
  final hasWidth = widthText.trim().isNotEmpty;
  final hasDepth = depthText.trim().isNotEmpty;
  if (hasWidth != hasDepth && width.error == null && depth.error == null) {
    errors['width'] = 'Width and depth are both required';
    errors['depth'] = 'Width and depth are both required';
  }

  if (errors.isNotEmpty) return StructureWrite.invalid(errors);

  final building = <String, dynamic>{'name': trimmedName};
  if (trimmedCode.isNotEmpty) building['code'] = trimmedCode;

  final payload = <String, dynamic>{
    'building': building,
    'basements': basements.value,
    'ground_floor': groundFloor,
    'floors': floors.value,
    'terrace': terrace,
    'units_per_floor': units.value,
    if (units.value! > 0) 'unit_floors': {'from': unitFrom, 'to': unitTo},
    if (units.value! > 0 && unitCategory.trim().isNotEmpty)
      'unit_category': unitCategory.trim(),
    if (units.value! > 0 && codePattern.trim().isNotEmpty)
      'code_pattern': codePattern.trim(),
    if (areas.isNotEmpty) 'common_areas': areas,
    'lifts': lifts.value,
    'staircases': staircases.value,
    if (height.value != null) 'floor_height': height.value,
    if (width.value != null && depth.value != null)
      'footprint': {'width': width.value, 'depth': depth.value},
  };
  return StructureWrite.ok(payload);
}

String towerGenerateSignature(Map<String, dynamic> payload) => jsonEncode(payload);

/// "33 nodes: 7 floors, 16 units, 6 common areas, 3 cores, 1 building".
String towerGenerateSummary(Map<String, dynamic> counts) {
  final parts = <String>[];
  void add(String key, String singular, String plural) {
    final count = asNum(counts[key])?.toInt() ?? 0;
    if (count <= 0) return;
    parts.add('$count ${count == 1 ? singular : plural}');
  }

  add('floors', 'floor', 'floors');
  add('units', 'unit', 'units');
  add('common_areas', 'common area', 'common areas');
  add('cores', 'core', 'cores');
  add('buildings', 'building', 'buildings');

  final listed = ['buildings', 'floors', 'units', 'common_areas', 'cores'];
  final total = asNum(counts['total'])?.toInt() ??
      listed.fold<int>(0, (sum, key) => sum + (asNum(counts[key])?.toInt() ?? 0));
  final noun = total == 1 ? 'node' : 'nodes';
  if (parts.isEmpty) return '$total $noun';
  return '$total $noun: ${parts.join(', ')}';
}

bool towerPreviewAccepted(Map<String, dynamic> data) {
  if (data['preview'] == false) return false;
  return data['preview'] == true || data.containsKey('counts') || data.containsKey('tree');
}

List<String> readTowerWarnings(Object? raw) {
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

List<TowerClash> readTowerClashes(Object? raw) {
  if (raw is! List) return const [];
  final out = <TowerClash>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final field = item['field']?.toString() ?? '';
    final value = item['value']?.toString() ?? '';
    final message = item['message']?.toString() ?? '';
    if (field.trim().isEmpty && value.trim().isEmpty && message.trim().isEmpty) continue;
    out.add(TowerClash(field: field, value: value, message: message));
  }
  return out;
}

String towerClashMessage(TowerClash clash) {
  final message = clash.message.trim();
  if (message.isNotEmpty) return message;
  final value = clash.value.trim();
  if (value.isNotEmpty) return '$value already exists';
  return 'This value already exists';
}

/// Maps a clash field onto the generator form.
String? towerClashFormField(String field) {
  switch (field.trim()) {
    case 'building.name':
      return 'name';
    case 'building.code':
    case 'code':
      return 'code';
    case 'code_pattern':
      return 'code_pattern';
    case '':
      return null;
    default:
      return field.trim();
  }
}

/// One node the tower commit will create, parented by [parentRef].
class TowerNodeDraft {
  const TowerNodeDraft({
    required this.ref,
    required this.body,
    this.parentRef,
  });

  final String ref;
  final String? parentRef;
  final Map<String, dynamic> body;
}

/// Local tower plan. Used when the generate endpoint is not on this contract yet.
class TowerPlan {
  const TowerPlan({required this.preview, required this.drafts});

  final Map<String, dynamic> preview;
  final List<TowerNodeDraft> drafts;
}

/// Builds the preview tree, counts, warnings and clashes from [payload].
///
/// [existing] is the project's current nodes. A clash does not write anything.
TowerPlan planTowerGenerate(
  Map<String, dynamic> payload, {
  List<Map<String, dynamic>> existing = const [],
}) {
  final building = payload['building'] is Map
      ? Map<String, dynamic>.from(payload['building'] as Map)
      : const <String, dynamic>{};
  final name = building['name']?.toString().trim() ?? '';
  final towerCode = building['code']?.toString().trim() ?? '';
  final basements = asNum(payload['basements'])?.toInt() ?? 0;
  final floorCount = asNum(payload['floors'])?.toInt() ?? 0;
  final ground = payload['ground_floor'] != false;
  final terrace = payload['terrace'] == true;
  final units = asNum(payload['units_per_floor'])?.toInt() ?? 0;
  final lifts = asNum(payload['lifts'])?.toInt() ?? 0;
  final staircases = asNum(payload['staircases'])?.toInt() ?? 0;
  final pattern = _patternOf(payload, units);
  final category = payload['unit_category']?.toString().trim() ?? '';
  final areas = _nameList(payload['common_areas']);
  final height = asNum(payload['floor_height']);
  final footprint = payload['footprint'] is Map
      ? Map<String, dynamic>.from(payload['footprint'] as Map)
      : const <String, dynamic>{};
  final width = asNum(footprint['width']);
  final depth = asNum(footprint['depth']);

  final levels = <_TowerLevel>[];
  for (var index = basements; index >= 1; index--) {
    levels.add(_TowerLevel(-index, 'Basement $index', 'Basement', false));
  }
  if (ground) levels.add(const _TowerLevel(0, 'Ground Floor', '', false));
  for (var index = 1; index <= floorCount; index++) {
    levels.add(_TowerLevel(index, 'Floor $index', '', false));
  }
  if (terrace) {
    final top = levels.isEmpty ? 0 : levels.last.level;
    levels.add(_TowerLevel(top + 1, 'Terrace', '', true));
  }

  var unitFrom = 1;
  var unitTo = floorCount;
  final range = payload['unit_floors'];
  if (range is Map) {
    unitFrom = asNum(range['from'])?.toInt() ?? unitFrom;
    unitTo = asNum(range['to'])?.toInt() ?? unitTo;
  }

  final usedCodes = <String>{
    for (final node in existing)
      if ((node['code']?.toString().trim() ?? '').isNotEmpty)
        node['code'].toString().trim().toLowerCase(),
  };
  final clashes = <Map<String, String>>[];
  final nameTaken = existing.any(
    (node) =>
        node['type'] == 'building' &&
        (node['name']?.toString().trim().toLowerCase() ?? '') == name.toLowerCase(),
  );
  if (name.isNotEmpty && nameTaken) {
    clashes.add({
      'field': 'building.name',
      'value': name,
      'message': 'A building with this name already exists',
    });
  }
  void claimCode(String code) {
    final key = code.trim().toLowerCase();
    if (key.isEmpty) return;
    if (usedCodes.contains(key)) {
      clashes.add({
        'field': 'code',
        'value': code,
        'message': 'Code is already used in this project',
      });
    }
    usedCodes.add(key);
  }

  claimCode(towerCode);

  final warnings = <String>[];
  final hasUnit = RegExp(r'\{unit(?::\d+)?\}').hasMatch(pattern);
  final hasLetter = pattern.contains('{unit_letter}');
  if (units > 1 && !hasUnit && !hasLetter) {
    warnings.add(
      'The code pattern has no {unit} token, so units on the same floor get the same code',
    );
  }

  final drafts = <TowerNodeDraft>[];
  final floorNodes = <Map<String, dynamic>>[];
  var unitCount = 0;
  var areaCount = 0;
  final buildingGeometry = _sizeGeometry(width: width, depth: depth);
  drafts.add(
    TowerNodeDraft(
      ref: 'b',
      body: {
        'type': 'building',
        'name': name,
        if (towerCode.isNotEmpty) 'code': towerCode,
        if (buildingGeometry != null) 'geometry': buildingGeometry,
      },
    ),
  );

  for (final level in levels) {
    final ref = 'f${level.level}';
    final floorGeometry = _sizeGeometry(height: height, width: width, depth: depth);
    drafts.add(
      TowerNodeDraft(
        ref: ref,
        parentRef: 'b',
        body: {
          'type': 'floor',
          'name': level.name,
          'level_number': level.level,
          if (level.category.isNotEmpty) 'category': level.category,
          if (floorGeometry != null) 'geometry': floorGeometry,
        },
      ),
    );
    final children = <Map<String, dynamic>>[];
    if (!level.terrace) {
      for (var index = 0; index < areas.length; index++) {
        final areaRef = '${ref}a${index + 1}';
        drafts.add(
          TowerNodeDraft(
            ref: areaRef,
            parentRef: ref,
            body: {
              'type': 'common_area',
              'name': areas[index],
            },
          ),
        );
        children.add({
          'ref': areaRef,
          'type': 'common_area',
          'name': areas[index],
          'children': <Map<String, dynamic>>[],
        });
        areaCount += 1;
      }
      final takesUnits = units > 0 && level.level >= unitFrom && level.level <= unitTo;
      if (takesUnits) {
        for (var unit = 1; unit <= units; unit++) {
          final code = applyTowerCodePattern(
            pattern: pattern,
            level: level.level,
            unit: unit,
            towerCode: towerCode,
          );
          claimCode(code);
          final unitRef = '${ref}u$unit';
          drafts.add(
            TowerNodeDraft(
              ref: unitRef,
              parentRef: ref,
              body: {
                'type': 'unit',
                'name': code,
                if (code.isNotEmpty) 'code': code,
                if (category.isNotEmpty) 'category': category,
              },
            ),
          );
          children.add({
            'ref': unitRef,
            'type': 'unit',
            'name': code,
            if (code.isNotEmpty) 'code': code,
            if (category.isNotEmpty) 'category': category,
            'children': <Map<String, dynamic>>[],
          });
          unitCount += 1;
        }
      }
    }
    floorNodes.add({
      'ref': ref,
      'type': 'floor',
      'name': level.name,
      'level_number': level.level,
      if (level.category.isNotEmpty) 'category': level.category,
      'children': children,
    });
  }

  final lowest = levels.isEmpty ? null : levels.first.level;
  final highest = levels.isEmpty ? null : levels.last.level;
  final coreNodes = <Map<String, dynamic>>[];
  if (lowest != null && highest != null) {
    void addCores(int count, String label) {
      for (var index = 1; index <= count; index++) {
        final coreName = '$label $index';
        final ref = '${label == 'Lift' ? 'l' : 's'}$index';
        drafts.add(
          TowerNodeDraft(
            ref: ref,
            parentRef: 'b',
            body: {
              'type': 'core',
              'name': coreName,
              'from_level': lowest,
              'to_level': highest,
            },
          ),
        );
        coreNodes.add({
          'ref': ref,
          'type': 'core',
          'name': coreName,
          'from_level': lowest,
          'to_level': highest,
          'children': <Map<String, dynamic>>[],
        });
      }
    }

    addCores(lifts, 'Lift');
    addCores(staircases, 'Staircase');
  }

  final counts = {
    'buildings': 1,
    'floors': levels.length,
    'units': unitCount,
    'common_areas': areaCount,
    'cores': lifts + staircases,
    'total': 1 + levels.length + unitCount + areaCount + lifts + staircases,
  };
  return TowerPlan(
    preview: {
      'preview': true,
      'counts': counts,
      'warnings': warnings,
      'clashes': clashes,
      'tree': [
        {
          'ref': 'b',
          'type': 'building',
          'name': name,
          if (towerCode.isNotEmpty) 'code': towerCode,
          'children': [...floorNodes, ...coreNodes],
        },
      ],
    },
    drafts: drafts,
  );
}

/// Writes [plan] with the existing create-node endpoint, parent before child.
Future<Map<String, dynamic>> commitPlannedTower({
  required Map<String, dynamic> payload,
  required List<Map<String, dynamic>> existing,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> body) createNode,
}) async {
  final plan = planTowerGenerate(payload, existing: existing);
  final ids = <String, String>{};
  for (final draft in plan.drafts) {
    final body = Map<String, dynamic>.from(draft.body);
    final parentRef = draft.parentRef;
    if (parentRef != null) body['parent'] = ids[parentRef];
    final created = await createNode(body);
    final id = idOf(created);
    if (id == null || id.isEmpty) {
      throw StateError('The structure node was not created');
    }
    ids[draft.ref] = id;
  }
  return {
    'preview': false,
    'counts': plan.preview['counts'],
    'warnings': plan.preview['warnings'],
    'created_nodes': plan.drafts.length,
  };
}

bool towerSpecPreview(Map<String, dynamic> data) =>
    data['counts'] is Map && data['tree'] is List;

bool towerSpecCommit(Map<String, dynamic> data) =>
    data['preview'] == false && data['counts'] is Map;

String _patternOf(Map<String, dynamic> payload, int units) {
  if (units <= 0) return towerCodePatternDefault;
  final text = payload['code_pattern']?.toString().trim() ?? '';
  if (text.isEmpty) return towerCodePatternDefault;
  return text;
}

List<String> _nameList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item.toString().trim().isNotEmpty) item.toString().trim(),
  ];
}

Map<String, num>? _sizeGeometry({num? height, num? width, num? depth}) {
  final geometry = <String, num>{};
  if (height != null) geometry['height'] = height;
  if (width != null) geometry['width'] = width;
  if (depth != null) geometry['depth'] = depth;
  if (geometry.isEmpty) return null;
  return geometry;
}

class _TowerLevel {
  const _TowerLevel(this.level, this.name, this.category, this.terrace);

  final int level;
  final String name;
  final String category;
  final bool terrace;
}

Map<String, String> towerClashFieldErrors(List<TowerClash> clashes) {
  final out = <String, String>{};
  for (final clash in clashes) {
    final key = towerClashFormField(clash.field);
    if (key == null) continue;
    final text = towerClashMessage(clash);
    final previous = out[key];
    out[key] = previous == null ? text : '$previous\n$text';
  }
  return out;
}

List<String> parseCommonAreaNames(String text) {
  final names = <String>[];
  for (final part in text.split(RegExp(r'[,\n]'))) {
    final name = part.trim();
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}

/// Applies `{tower}`, `{floor}`, `{floor:02}`, `{level}`, `{unit}`, `{unit:02}`, `{unit_letter}`.
String applyTowerCodePattern({
  required String pattern,
  required int level,
  required int unit,
  required String towerCode,
}) {
  final token = RegExp(r'\{([a-zA-Z_]+)(?::(\d+))?\}');
  return pattern.replaceAllMapped(token, (match) {
    final name = match.group(1)!.toLowerCase();
    final width = int.tryParse(match.group(2) ?? '');
    switch (name) {
      case 'tower':
      case 'building':
        return towerCode;
      case 'floor':
        return _floorToken(level, width);
      case 'level':
        return _padSigned(level, width);
      case 'unit':
        return _pad('$unit', width);
      case 'unit_letter':
        return _unitLetter(unit);
      default:
        return match.group(0)!;
    }
  });
}

String towerPreviewTitle(Map<String, dynamic> node) {
  final name = node['name']?.toString().trim() ?? '';
  final code = node['code']?.toString().trim() ?? '';
  if (name.isEmpty) return code.isEmpty ? 'Node' : code;
  if (code.isNotEmpty && code != name) return '$name · $code';
  return name;
}

String towerPreviewSubtitle(Map<String, dynamic> node) {
  final type = node['type']?.toString() ?? '';
  final label = structureNodeTypeLabels[type] ?? (type.isEmpty ? 'Node' : type);
  final parts = <String>[label];
  if (type == 'floor') {
    final level = asNum(node['level_number']);
    if (level != null) {
      final shown = level == level.roundToDouble() ? level.toInt() : level;
      parts.add('level $shown');
    }
  }
  final category = node['category']?.toString().trim() ?? '';
  if (category.isNotEmpty) parts.add(category);
  return parts.join(' · ');
}

String _floorToken(int level, int? width) {
  if (level == 0) return 'G';
  if (level < 0) return 'B${_pad('${level.abs()}', width)}';
  return _pad('$level', width);
}

String _padSigned(int value, int? width) {
  if (value < 0) return '-${_pad('${value.abs()}', width)}';
  return _pad('$value', width);
}

String _pad(String digits, int? width) {
  if (width == null || width <= digits.length) return digits;
  return digits.padLeft(width, '0');
}

String _unitLetter(int unit) {
  if (unit <= 0) return '';
  var n = unit;
  final chars = <String>[];
  while (n > 0) {
    n -= 1;
    chars.add(String.fromCharCode(65 + (n % 26)));
    n ~/= 26;
  }
  return chars.reversed.join();
}

class _ParsedInt {
  const _ParsedInt.ok(this.value) : error = null;
  const _ParsedInt.bad(this.error) : value = null;

  final int? value;
  final String? error;
}

class _ParsedNum {
  const _ParsedNum.ok(this.value) : error = null;
  const _ParsedNum.bad(this.error) : value = null;

  final num? value;
  final String? error;
}

_ParsedInt _count(String text, {required String label, required int max}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const _ParsedInt.ok(0);
  final value = int.tryParse(trimmed);
  if (value == null) return _ParsedInt.bad('$label must be a whole number');
  if (value < 0 || value > max) {
    return _ParsedInt.bad('$label must be between 0 and $max');
  }
  return _ParsedInt.ok(value);
}

_ParsedInt _whole(String text, {required String label, required bool required}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    if (required) return _ParsedInt.bad('$label is required');
    return const _ParsedInt.ok(null);
  }
  final value = int.tryParse(trimmed);
  if (value == null) return _ParsedInt.bad('$label must be a whole number');
  return _ParsedInt.ok(value);
}

_ParsedNum _optionalSize(
  String text, {
  required String label,
  required num min,
  required num max,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const _ParsedNum.ok(null);
  final value = num.tryParse(trimmed);
  if (value == null) return _ParsedNum.bad('$label must be a number');
  if (value < min || value > max) {
    return _ParsedNum.bad('$label must be between $min and $max');
  }
  return _ParsedNum.ok(value);
}
