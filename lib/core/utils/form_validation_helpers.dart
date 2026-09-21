import '../network/api_exception.dart';

/// Tracks inline field errors for picker/custom fields outside [FormField].
class FieldErrors {
  final Map<String, String> _map = {};

  String? operator [](String key) => _map[key];

  void set(String key, String? message) {
    if (message == null || message.trim().isEmpty) {
      _map.remove(key);
    } else {
      _map[key] = message.trim();
    }
  }

  void clear() => _map.clear();

  void merge(Map<String, String> other) => _map.addAll(other);

  bool get hasErrors => _map.isNotEmpty;

  List<String> get messages => _map.values.toList();

  String get summary => messages.join('\n');
}

String? requiredSelection(String? id, String label) {
  if (id == null || id.trim().isEmpty) return '$label is required';
  return null;
}

String? requiredDate(DateTime? date, String label) {
  if (date == null) return '$label is required';
  return null;
}

String? dateRangeError({
  required DateTime? start,
  required DateTime? end,
  String startLabel = 'Start date',
  String endLabel = 'End date',
}) {
  if (start != null && end != null && end.isBefore(start)) {
    return '$endLabel cannot be before $startLabel';
  }
  return null;
}

String? requiredList(List<dynamic> values, String label) {
  if (values.isEmpty) return '$label is required';
  return null;
}

/// Maps backend Joi `details[].field` keys to form field keys.
Map<String, String> apiFieldErrors(ApiException e) {
  final out = <String, String>{};
  for (final raw in e.fieldErrors) {
    if (raw is! Map) continue;
    final field = raw['field']?.toString() ?? '';
    final message = raw['message']?.toString() ?? 'Invalid value';
    final key = _mapApiFieldKey(field);
    if (key != null) out[key] = message;
  }
  return out;
}

String? _mapApiFieldKey(String field) {
  const known = {
    'project_name': 'projectName',
    'site': 'site',
    'timeline.start_date': 'startDate',
    'timeline.end_date': 'endDate',
    'project_manager': 'manager',
    'project_lead': 'lead',
    'title': 'title',
    'project': 'project',
    'coordinator': 'coordinator',
    'assignedMembers': 'members',
    'start_date': 'startDate',
    'due_date': 'dueDate',
    'email': 'email',
    'password': 'password',
    'name': 'name',
    'phone': 'phone',
  };
  if (known.containsKey(field)) return known[field];
  if (field.isNotEmpty) return field;
  return null;
}

String formatApiErrorSummary(ApiException e) {
  final fields = apiFieldErrors(e);
  if (fields.isNotEmpty) {
    return fields.entries.map((e) => e.value).join('\n');
  }
  return e.message;
}
