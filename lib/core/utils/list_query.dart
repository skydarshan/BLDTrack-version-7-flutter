/// RR list: digits → PR number; otherwise title `search` (backend ANDs both).
Map<String, dynamic> rrSearchQuery(String raw) {
  final q = raw.trim();
  if (q.isEmpty) return const {};
  final n = int.tryParse(q);
  if (n != null) return {'requisition_request_number': n};
  return {'search': q};
}

String? isoDateOnly(DateTime? value) {
  if (value == null) return null;
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String listEmptyMessage({
  required String noun,
  String search = '',
  String? filterLabel,
}) {
  final q = search.trim();
  if (q.isNotEmpty) {
    return 'No $noun match “$q”. Try another search.';
  }
  if (filterLabel != null && filterLabel.trim().isNotEmpty) {
    return 'No $noun in $filterLabel.';
  }
  return 'No $noun yet.';
}
