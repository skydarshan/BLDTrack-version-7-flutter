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
