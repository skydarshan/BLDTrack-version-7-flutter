import '../../../core/network/api_exception.dart';

/// One `{ field, message }` entry from a structure error envelope.
class StructureFieldDetail {
  const StructureFieldDetail({required this.field, required this.message});

  final String field;
  final String message;
}

/// Structure API error: `{ success: false, message, details? }`.
///
/// 400 highlights [fieldMessages]. 403 is no access. 404 is not found.
/// A 409 is either a delete confirmation (`cascade` / `unlink_tasks`) or a
/// clash the user can fix by changing the highlighted field.
class StructureApiError {
  const StructureApiError({
    required this.statusCode,
    required this.message,
    this.details = const [],
  });

  final int? statusCode;
  final String message;
  final List<StructureFieldDetail> details;

  bool get isNoAccess => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  bool get needsCascade => _hasField('cascade');

  bool get needsUnlinkTasks => _hasField('unlink_tasks');

  /// Delete must be confirmed, then retried with the matching query flag.
  bool get isDeleteConflict =>
      statusCode == 409 && (needsCascade || needsUnlinkTasks);

  /// Show [message] and highlight [fieldMessages].
  bool get highlightFields =>
      statusCode == 400 || (statusCode == 409 && !isDeleteConflict);

  String get notFoundMessage {
    final text = message.trim();
    if (text.isEmpty) return 'Not found';
    return text;
  }

  /// Form keys to highlight. Delete flags are not form fields.
  Map<String, String> get fieldMessages {
    final out = <String, String>{};
    for (final detail in details) {
      if (detail.field == 'cascade' || detail.field == 'unlink_tasks') continue;
      final key = structureFormField(detail.field);
      if (key == null) continue;
      final text = detail.message.trim();
      out[key] = text.isEmpty ? message : text;
    }
    return out;
  }

  String messageFor(String field) {
    for (final detail in details) {
      if (detail.field != field) continue;
      final text = detail.message.trim();
      if (text.isNotEmpty) return text;
    }
    return message;
  }

  bool _hasField(String field) => details.any((detail) => detail.field == field);
}

StructureApiError readStructureError(ApiException error) {
  final details = <StructureFieldDetail>[];
  for (final raw in error.fieldErrors) {
    if (raw is! Map) continue;
    details.add(
      StructureFieldDetail(
        field: raw['field']?.toString() ?? '',
        message: raw['message']?.toString() ?? '',
      ),
    );
  }
  return StructureApiError(
    statusCode: error.statusCode,
    message: _structureErrorMessage(error.statusCode, error.message, details),
    details: details,
  );
}

String _structureErrorMessage(
  int? statusCode,
  String message,
  List<StructureFieldDetail> details,
) {
  final text = message.trim();
  if (text.isNotEmpty) return text;
  for (final detail in details) {
    final detailText = detail.message.trim();
    if (detailText.isNotEmpty) return detailText;
  }
  switch (statusCode) {
    case 403:
      return 'You do not have access to this project.';
    case 404:
      return 'Not found';
    default:
      return 'Something went wrong.';
  }
}

/// Maps `details[].field` onto the structure form.
///
/// `building.name` is the generator clash for the building name.
/// Task-link fields (`structure_nodes`, `floor_level`) highlight Structure.
String? structureFormField(String field) {
  final normalized = field.trim();
  if (normalized.isEmpty) return null;
  if (normalized == 'building.name') return 'name';
  if (normalized == 'building.code') return 'code';
  if (normalized == 'structure_nodes' ||
      normalized.startsWith('structure_nodes.') ||
      normalized.startsWith('structure_nodes[') ||
      normalized == 'floor_level' ||
      normalized.endsWith('.floor_level')) {
    return 'structure';
  }
  return normalized;
}
