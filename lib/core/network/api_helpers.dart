/// Shared response unwrapping for `/api/v1` envelopes.
library;

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
  if (data is Map) return Map<String, dynamic>.from(data);
  return root;
}

/// First non-null field among [keys] (snake_case / camelCase aliases).
dynamic firstNonNull(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final value = map[key];
    if (value != null) return value;
  }
  return null;
}

Map<String, dynamic> firstMap(Map<String, dynamic>? map, List<String> keys) {
  final value = firstNonNull(map, keys);
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

num? asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

String? mongoId(dynamic value) {
  final id = idOf(value);
  if (id == null || id.isEmpty || id == 'null') return null;
  return id;
}

Map<String, dynamic> rcStatusPayload(Map<String, dynamic> doc, String status) {
  return {
    'status': status,
    'items': rcItemsPayload(doc['items']),
    'vendors_total': rcVendorsTotalPayload(doc['vendors_total']),
    if ((doc['remarks']?.toString() ?? '').trim().isNotEmpty) 'remarks': doc['remarks'],
  };
}

List<Map<String, dynamic>> rcItemsPayload(dynamic items) {
  return asMapList(items is List ? items : const []).map((line) {
    final itemId = mongoId(line['item_id'] ?? line['item']);
    final vendors = asMapList(line['vendors'] is List ? line['vendors'] : const []);
    final brands = line['brandName'];
    final uom = mongoId(line['uom']);
    final baseUom = mongoId(line['base_uom']);
    final baseQty = asNum(line['base_qty']);
    return <String, dynamic>{
      if (itemId != null) 'item_id': itemId,
      'qty': asNum(line['qty']) ?? 1,
      'remark': line['remark'] ?? '',
      'procurement_remarks': line['procurement_remarks'] ?? '',
      'gst': asNum(line['gst']) ?? 0,
      'budget': asNum(line['budget']) ?? 0,
      'budget_subtotal': asNum(line['budget_subtotal']) ?? 0,
      'brandName': brands is List
          ? brands.map(mongoId).whereType<String>().toList()
          : <String>[],
      if (uom != null) 'uom': uom,
      if (baseUom != null) 'base_uom': baseUom,
      if (baseQty != null) 'base_qty': baseQty,
      'vendors': vendors
          .map((vendor) {
            final vendorId = mongoId(vendor['vendor_id'] ?? vendor['vendor']);
            return <String, dynamic>{
              if (vendorId != null) 'vendor_id': vendorId,
              'vendor_name': vendor['vendor_name'] ?? '',
              'requiredQty': asNum(vendor['requiredQty']) ?? 0,
              'preferred': vendor['preferred'] == true,
              'rate': asNum(vendor['rate']) ?? 0,
              'amount': asNum(vendor['amount']) ?? 0,
            };
          })
          .toList(),
    };
  }).where((line) => line['item_id'] != null).toList();
}

List<Map<String, dynamic>> rcVendorsTotalPayload(dynamic list) {
  return asMapList(list is List ? list : const []).map((vendor) {
    final vendorId = mongoId(vendor['vendor_id'] ?? vendor['vendor']);
    return <String, dynamic>{
      if (vendorId != null) 'vendor_id': vendorId,
      'subtotal': asNum(vendor['subtotal']) ?? 0,
      'total_tax': asNum(vendor['total_tax']) ?? 0,
      'freight_charges': asNum(vendor['freight_charges']) ?? 0,
      'other_charges': asNum(vendor['other_charges']) ?? 0,
      'other_tax': asNum(vendor['other_tax']) ?? 0,
      'freight_tax': asNum(vendor['freight_tax']) ?? 0,
      'total_amount': asNum(vendor['total_amount']) ?? 0,
      'preferred': vendor['preferred'] == true,
      'vendor_quotation': vendor['vendor_quotation'] ?? '',
      'paymentTerms': vendor['paymentTerms'] ?? '',
      'deliveryTerms': vendor['deliveryTerms'] ?? '',
      'vendorRemark': vendor['vendorRemark'] ?? '',
    };
  }).where((vendor) => vendor['vendor_id'] != null).toList();
}

List<Map<String, dynamic>> transferDispatchItems(Map<String, dynamic> doc) {
  return asMapList(doc['items'] is List ? doc['items'] : const []).map((line) {
    final itemId = mongoId(line['item_id'] ?? line['item']);
    final qty = asNum(
      line['requested_quantity'] ?? line['dispatched_quantity'] ?? line['quantity'],
    );
    return <String, dynamic>{
      if (itemId != null) 'item_id': itemId,
      if (qty != null) 'dispatched_quantity': qty,
    };
  }).where((line) {
    final qty = line['dispatched_quantity'];
    return line['item_id'] != null && qty is num && qty > 0;
  }).toList();
}

List<Map<String, dynamic>> transferReceiveItems(Map<String, dynamic> doc) {
  return asMapList(doc['items'] is List ? doc['items'] : const []).map((line) {
    final itemId = mongoId(line['item_id'] ?? line['item']);
    final dispatched = asNum(
          line['dispatched_quantity'] ?? line['requested_quantity'] ?? line['quantity'],
        ) ??
        0;
    final already = asNum(line['received_quantity']) ?? 0;
    final remaining = dispatched - already;
    return <String, dynamic>{
      if (itemId != null) 'item_id': itemId,
      if (remaining > 0) 'received_quantity': remaining,
    };
  }).where((line) => line['item_id'] != null && line['received_quantity'] != null).toList();
}

/// Maps React web notification links onto Flutter go_router paths.
String? flutterNotificationPath(String? link) {
  if (link == null || link.isEmpty) return null;
  var path = link.trim();
  if (!path.startsWith('/')) return null;
  final queryAt = path.indexOf('?');
  if (queryAt >= 0) path = path.substring(0, queryAt);

  if (path.startsWith('/procurement/') ||
      path.startsWith('/inventory/') ||
      path.startsWith('/pms/') ||
      path.startsWith('/dmr/') ||
      path == '/notifications' ||
      path == '/billing') {
    return path;
  }

  final taskId = RegExp(r'^/tasks/([a-fA-F0-9]{24})$').firstMatch(path);
  if (taskId != null) return '/pms/tasks/${taskId[1]}';
  if (path == '/tasks/approvals/pending' || path == '/tasks/completions/ready') {
    return '/pms/approvals';
  }
  final projectId = RegExp(r'^/projects/([a-fA-F0-9]{24})$').firstMatch(path);
  if (projectId != null) return '/pms/projects/${projectId[1]}';
  final rr = RegExp(r'^/requisition-requests/([a-fA-F0-9]{24})$').firstMatch(path);
  if (rr != null) return '/procurement/rr/${rr[1]}';
  final rc = RegExp(r'^/rate-comparatives/([a-fA-F0-9]{24})$').firstMatch(path);
  if (rc != null) return '/procurement/rc/${rc[1]}';
  final po = RegExp(r'^/purchase-orders/([a-fA-F0-9]{24})$').firstMatch(path);
  if (po != null) return '/procurement/po/${po[1]}';
  final dmr = RegExp(r'^/(?:dmr-purchase-orders|dmr)/([a-fA-F0-9]{24})$').firstMatch(path);
  if (dmr != null) return '/dmr/status/${dmr[1]}';
  final transfer = RegExp(r'^/inter-site-transfers/([a-fA-F0-9]{24})$').firstMatch(path);
  if (transfer != null) return '/inventory/transfers/${transfer[1]}';
  return path;
}

String planPriceLabel(Map<String, dynamic> plan) {
  final prices = plan['prices'];
  if (prices is List && prices.isNotEmpty && prices.first is Map) {
    final first = Map<String, dynamic>.from(prices.first as Map);
    final amount = first['amount'] ?? first['price'] ?? first['unit_amount'] ?? '';
    final currency = first['currency'] ?? plan['currency'] ?? '';
    return '$amount $currency'.trim();
  }
  return '${plan['price'] ?? plan['amount'] ?? ''} ${plan['currency'] ?? ''}'.trim();
}

List<dynamic> unwrapDataList(Map<String, dynamic>? root) {
  if (root == null) return const [];
  final data = root['data'];
  if (data is List) return data;
  if (data is Map) {
    for (final key in ['notifications', 'items', 'entries', 'tree', 'roots', 'data']) {
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
