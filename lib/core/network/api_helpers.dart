/// Shared response unwrapping for `/api/v1` envelopes.

class PaginatedResult {
  const PaginatedResult({
    required this.items,
    this.pagination,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, dynamic>? pagination;
}

Map<String, dynamic>? cleanQuery(Map<String, dynamic>? params) {
  if (params == null) return null;
  final out = <String, dynamic>{};
  params.forEach((k, v) {
    if (v == null) return;
    if (v is String && v.isEmpty) return;
    out[k] = v;
  });
  return out.isEmpty ? null : out;
}

List<Map<String, dynamic>> asMapList(List<dynamic> list) => list
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

Map<String, dynamic> unwrapDataMap(Map<String, dynamic>? root) {
  if (root == null) return const {};
  final data = root['data'];
  if (data is Map<String, dynamic>) return data;
  return root;
}

List<dynamic> unwrapDataList(Map<String, dynamic>? root) {
  if (root == null) return const [];
  final data = root['data'];
  if (data is List) return data;
  if (data is Map) {
    for (final key in ['notifications', 'items', 'tree', 'roots', 'data']) {
      final nested = data[key];
      if (nested is List) return nested;
    }
  }
  return const [];
}

/// Notifications list envelope: `data: { notifications: [...], unreadCount }`.
class NotificationListResult {
  const NotificationListResult({
    required this.items,
    this.unreadCount = 0,
    this.pagination,
  });

  final List<Map<String, dynamic>> items;
  final int unreadCount;
  final Map<String, dynamic>? pagination;
}

NotificationListResult unwrapNotifications(Map<String, dynamic>? root) {
  if (root == null) {
    return const NotificationListResult(items: []);
  }
  final data = root['data'];
  if (data is Map) {
    final list = data['notifications'];
    final unread = data['unreadCount'] ?? data['count'] ?? data['unread'];
    return NotificationListResult(
      items: list is List ? asMapList(list) : const [],
      unreadCount: unread is num ? unread.toInt() : 0,
      pagination: unwrapPagination(root),
    );
  }
  if (data is List) {
    return NotificationListResult(
      items: asMapList(data),
      pagination: unwrapPagination(root),
    );
  }
  return const NotificationListResult(items: []);
}

/// Format procurement line qty with UOM (reads backend snapshot fields).
String formatLineQtyUom(Map<String, dynamic>? line) {
  if (line == null) return '—';
  final qty = line['qty'] ?? line['quantity'] ?? line['received_qty'];
  final uom = line['uom'];
  String unit = '';
  if (uom is Map) {
    unit = uom['unit']?.toString() ?? uom['name']?.toString() ?? '';
  } else if (uom is String) {
    unit = uom;
  }
  final baseQty = line['base_qty'] ?? line['base_accepted_qty'] ?? line['base_received_qty'];
  final baseUom = line['base_uom'];
  String baseUnit = '';
  if (baseUom is Map) {
    baseUnit = baseUom['unit']?.toString() ?? baseUom['name']?.toString() ?? '';
  } else if (baseUom is String) {
    baseUnit = baseUom;
  }
  final qtyStr = qty?.toString() ?? '—';
  final main = unit.isNotEmpty ? '$qtyStr $unit' : qtyStr;
  if (baseQty != null && baseUnit.isNotEmpty && baseQty.toString() != qtyStr) {
    return '$main (${baseQty.toString()} $baseUnit stock)';
  }
  return main;
}

Map<String, dynamic>? unwrapPagination(Map<String, dynamic>? root) {
  if (root == null) return null;
  final pagination = root['pagination'];
  if (pagination is Map<String, dynamic>) return pagination;
  return null;
}

String? idOf(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) {
    final id = value['_id'] ?? value['id'];
    return id?.toString();
  }
  return value.toString();
}

String labelOf(dynamic value, {String fallback = '—'}) {
  if (value == null) return fallback;
  if (value is String) return value.isEmpty ? fallback : value;
  if (value is Map) {
    final name = value['name'] ??
        value['site_name'] ??
        value['project_name'] ??
        value['title'] ??
        value['email'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString();
    }
    return idOf(value) ?? fallback;
  }
  return value.toString();
}

String formatDate(dynamic value) {
  if (value == null) return '—';
  final raw = value.toString();
  if (raw.isEmpty) return '—';
  final d = DateTime.tryParse(raw);
  if (d == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
  final local = d.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yyyy = local.year.toString();
  return '$dd/$mm/$yyyy';
}

String formatDateTime(dynamic value) {
  if (value == null) return '—';
  final d = DateTime.tryParse(value.toString());
  if (d == null) return value.toString();
  final local = d.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yyyy = local.year.toString();
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy $hh:$min';
}

String statusLabel(String? status) {
  if (status == null || status.isEmpty) return '—';
  return status.replaceAll('_', ' ');
}
