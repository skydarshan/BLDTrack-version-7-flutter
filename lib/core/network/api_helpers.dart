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
  final uri = Uri.tryParse(path);
  final open = uri?.queryParameters['open'] ?? '';
  final filter = uri?.queryParameters['filter'] ?? '';
  final tab = uri?.queryParameters['tab'] ?? '';
  final queryAt = path.indexOf('?');
  if (queryAt >= 0) path = path.substring(0, queryAt);

  if (path.startsWith('/dashboard/dpr-approvals') ||
      path.startsWith('/daily-progress-reports/approvals')) {
    return open.isEmpty ? '/pms/dpr/approvals' : '/pms/dpr/approvals?open=$open';
  }
  if (path.startsWith('/daily-progress-reports/missing') ||
      filter == 'missing' ||
      tab == 'missing') {
    if (path.contains('daily-progress') || path.contains('dpr')) {
      return '/pms/dpr?tab=missing';
    }
  }
  final dprId = RegExp(r'^/daily-progress-reports/([a-fA-F0-9]{24})$').firstMatch(path);
  if (dprId != null) return '/pms/dpr/${dprId[1]}';
  if (path.startsWith('/dashboard/daily-progress-reports')) {
    if (open.isNotEmpty) return '/pms/dpr/$open';
    return '/pms/dpr';
  }

  if (path.startsWith('/procurement/') ||
      path.startsWith('/inventory/') ||
      path.startsWith('/pms/') ||
      path.startsWith('/dmr/') ||
      path == '/notifications' ||
      path == '/billing') {
    return path;
  }

  final nestedTask = RegExp(
    r'^/(?:dashboard/)?projects/([a-fA-F0-9]{24})/tasks/([a-fA-F0-9]{24})',
  ).firstMatch(path);
  if (nestedTask != null) return '/pms/tasks/${nestedTask[2]}';

  final taskId = RegExp(r'^/tasks/([a-fA-F0-9]{24})$').firstMatch(path);
  if (taskId != null) return '/pms/tasks/${taskId[1]}';
  if (path == '/tasks/approvals/pending' ||
      path == '/tasks/completions/ready' ||
      path.startsWith('/dashboard/task-approvals') ||
      path.startsWith('/dashboard/task-ready-completion')) {
    return open.isEmpty ? '/pms/approvals' : '/pms/tasks/$open';
  }
  if (path.startsWith('/dashboard/tasks')) {
    return open.isEmpty ? '/pms/tasks' : '/pms/tasks/$open';
  }
  final projectId = RegExp(r'^/(?:dashboard/)?projects/([a-fA-F0-9]{24})$').firstMatch(path);
  if (projectId != null) return '/pms/projects/${projectId[1]}';
  if (path == '/dashboard/projects' || path == '/projects') return '/pms/projects';
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

  if (path.startsWith('/dashboard/notifications')) return '/notifications';
  if (path.startsWith('/dashboard/requisition-approvals')) {
    return open.isEmpty ? '/procurement/approvals' : '/procurement/rr/$open';
  }
  if (path.startsWith('/dashboard/requisition-requests')) {
    return open.isEmpty ? '/procurement/rr' : '/procurement/rr/$open';
  }
  if (path.startsWith('/dashboard/issued-material')) return '/inventory/imr';
  if (path.startsWith('/dashboard/intersite')) {
    return open.isEmpty ? '/inventory/transfers' : '/inventory/transfers/$open';
  }
  if (path.startsWith('/dashboard/scrap')) {
    return open.isEmpty ? '/inventory/scrap' : '/inventory/scrap/$open';
  }
  if (path.startsWith('/dashboard/inventory')) return '/inventory';
  return null;
}

/// Screen to open when the user taps a notification row or a push alert.
String notificationRouteFor(Map<String, dynamic> row) {
  final metadata = row['metadata'];
  final meta = metadata is Map ? Map<String, dynamic>.from(metadata) : null;
  final mapped = flutterNotificationPath(row['link']?.toString() ?? meta?['link']?.toString());
  if (mapped != null) return mapped;

  final entityId = idOf(row['entityId'] ?? meta?['entityId']);
  final projectId = idOf(row['project'] ?? meta?['projectId'] ?? meta?['project']);
  final section = meta?['section']?.toString();
  switch (section) {
    case 'project_completed':
    case 'project_leadership':
      final id = entityId ?? projectId;
      return id == null ? '/pms/projects' : '/pms/projects/$id';
    case 'ready':
    case 'pending_approval':
    case 'revise':
    case 'assignment':
    case 'completed':
    case 'comment':
      return entityId == null ? '/pms/tasks' : '/pms/tasks/$entityId';
  }

  switch (row['type']?.toString()) {
    case 'completion_ready':
    case 'completion_pending_approval':
    case 'task_revised':
    case 'task_comment':
    case 'task_assigned':
    case 'task_coordinator_assigned':
    case 'task_completed':
    case 'task_reminder':
      return entityId == null ? '/pms/tasks' : '/pms/tasks/$entityId';
    case 'project_completed':
    case 'project_reminder':
    case 'project_manager_assigned':
    case 'project_lead_assigned':
      final id = entityId ?? projectId;
      return id == null ? '/pms/projects' : '/pms/projects/$id';
    case 'rr_approval_pending':
    case 'rr_approval_step2_pending':
      return entityId == null ? '/procurement/approvals' : '/procurement/rr/$entityId';
    case 'rr_approved':
    case 'rr_revised':
    case 'rr_rejected':
      return entityId == null ? '/procurement/rr' : '/procurement/rr/$entityId';
    case 'inventory_stock_received':
      return '/inventory';
    case 'inventory_material_issued':
      return entityId == null ? '/inventory/imr' : '/inventory/imr/$entityId';
    case 'inventory_transfer_created':
    case 'inventory_transfer_received':
      return entityId == null ? '/inventory/transfers' : '/inventory/transfers/$entityId';
    case 'inventory_scrap_recorded':
      return entityId == null ? '/inventory/scrap' : '/inventory/scrap/$entityId';
    case 'dpr_pending_approval':
      return entityId == null ? '/pms/dpr/approvals' : '/pms/dpr/approvals?open=$entityId';
    case 'dpr_revised':
    case 'dpr_approved':
      return entityId == null ? '/pms/dpr' : '/pms/dpr/$entityId';
    case 'dpr_missing':
      return '/pms/dpr?tab=missing';
  }

  if (entityId == null) return '/notifications';
  switch (row['entityType']?.toString() ?? meta?['entityType']?.toString()) {
    case 'dpr':
    case 'daily_progress_report':
    case 'dailyProgressReport':
      return '/pms/dpr/$entityId';
    case 'task':
      return '/pms/tasks/$entityId';
    case 'project':
      return '/pms/projects/$entityId';
    case 'requisition':
    case 'requisition_request':
      return '/procurement/rr/$entityId';
    case 'rate_comparative':
      return '/procurement/rc/$entityId';
    case 'purchase_order':
    case 'requisition_order':
      return '/procurement/po/$entityId';
    case 'dmr':
    case 'dmr_purchase_order':
      return '/dmr/status/$entityId';
    case 'issued_material':
    case 'material_issue':
      return '/inventory/imr/$entityId';
    case 'transfer':
    case 'inter_site_transfer':
      return '/inventory/transfers/$entityId';
    case 'scrap':
      return '/inventory/scrap/$entityId';
  }
  return '/notifications';
}

bool notificationIsUnread(Map<String, dynamic> row) {
  return row['read'] != true && row['isRead'] != true;
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
    const keys = [
      'dmrPurchaseOrders',
      'dmrRequisitionOrders',
      'dmrEntries',
      'imperestDmrEntries',
      'requisitionOrders',
      'rateComparatives',
      'notifications',
      'items',
      'entries',
      'tree',
      'roots',
      'data',
      'sites',
      'categories',
      'subCategories',
      'vendors',
      'users',
      'companies',
      'brands',
      'uoms',
      'gsts',
      'locations',
      'contractors',
      'activities',
      'subActivities',
      'siteStaff',
      'roles',
      'projects',
      'comments',
      'requisitionRequests',
      'transfers',
    ];
    List<dynamic>? emptyMatch;
    for (final key in keys) {
      final nested = data[key];
      if (nested is! List) continue;
      if (nested.isNotEmpty) return nested;
      emptyMatch ??= nested;
    }
    for (final value in data.values) {
      if (value is List && value.isNotEmpty && value.first is Map) {
        return value;
      }
    }
    if (emptyMatch != null) return emptyMatch;
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
  final top = root['pagination'];
  if (top is Map) return Map<String, dynamic>.from(top);
  final data = root['data'];
  if (data is Map) {
    final nested = data['pagination'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
  }
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

bool looksLikeObjectId(String? value) {
  if (value == null || value.length != 24) return false;
  return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value);
}

String? _readableName(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || looksLikeObjectId(text)) return null;
  return text;
}

String labelOf(dynamic value, {String fallback = '—'}) {
  if (value == null) return fallback;
  if (value is String) return _readableName(value) ?? fallback;
  if (value is Map) {
    const keys = [
      'item_name',
      'vendor_name',
      'site_name',
      'project_name',
      'company_name',
      'companyName',
      'brand_name',
      'uom_name',
      'gst_name',
      'category_name',
      'subcategory_name',
      'location_name',
      'activity_name',
      'sub_activity_name',
      'contractor_name',
      'employee_name',
      'full_name',
      'fullName',
      'name',
      'title',
      'email',
    ];
    for (final key in keys) {
      final name = _readableName(value[key]);
      if (name != null) return name;
    }
    for (final nested in [
      value['item_id'],
      value['item'],
      value['vendor'],
      value['site'],
      value['category'],
      value['sub_category'],
      value['uom'],
      value['gst'],
      value['role'],
      value['location'],
    ]) {
      if (nested is Map) {
        final name = labelOf(nested, fallback: '');
        if (name.isNotEmpty) return name;
      }
    }
    return fallback;
  }
  return _readableName(value.toString()) ?? fallback;
}

/// Display name for a procurement / inventory line item.
String itemLabel(dynamic line, {String fallback = '—'}) {
  if (line == null) return fallback;
  if (line is String) return _readableName(line) ?? fallback;
  if (line is! Map) return labelOf(line, fallback: fallback);
  final map = Map<String, dynamic>.from(line);
  for (final key in [
    'item_name',
    'itemName',
    'name',
    'item_id',
    'item',
    'category_id',
    'sub_category_id',
  ]) {
    final value = map[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    final label = labelOf(value, fallback: '');
    if (label.isNotEmpty) return label;
  }
  return fallback;
}

String siteNameOf(Map<String, dynamic> row) {
  final direct = labelOf(row['site'] ?? row['site_id'], fallback: '');
  if (direct.isNotEmpty) return direct;
  final named = _readableName(row['site_name']);
  if (named != null) return named;
  final rr = row['requisition_request_id'];
  if (rr is Map) {
    final nested = labelOf(rr['site'], fallback: '');
    if (nested.isNotEmpty) return nested;
  }
  return '';
}

String vendorNamesOf(Map<String, dynamic> row) {
  final names = <String>[];
  void add(dynamic value) {
    final text = value is String ? (_readableName(value) ?? '') : labelOf(value, fallback: '');
    final trimmed = text.trim();
    if (trimmed.isEmpty || names.contains(trimmed)) return;
    names.add(trimmed);
  }

  final detail = row['vendor_detail'];
  if (detail is Map) add(detail['vendor_name']);
  add(row['vendor_name']);
  add(row['vendor']);
  add(row['vendor_id']);

  void addVendorList(dynamic raw) {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map) continue;
      add(entry['vendor_name']);
      add(entry['vendor_id']);
      add(entry['vendor']);
    }
  }

  addVendorList(row['vendors_total']);
  addVendorList(row['vendors']);
  final items = row['items'];
  if (items is List) {
    for (final line in items) {
      if (line is! Map) continue;
      addVendorList(line['vendors']);
    }
  }
  return names.join(', ');
}

List<Map<String, dynamic>> lineItemsOf(Map<String, dynamic>? doc) {
  if (doc == null) return const [];
  dynamic raw = doc['items'];
  if (raw is! List || raw.isEmpty) raw = doc['dmr_items'];
  if (raw is! List) return const [];
  final items = asMapList(raw);
  doc['items'] = items;
  return items;
}

String itemQtySubtitle(Map<String, dynamic> line) {
  final qty = firstNonNull(line, [
    'qty',
    'issued_Qty',
    'issued_qty',
    'quantity',
    'requested_quantity',
    'received_quantity',
    'scrap_qty',
  ]);
  final rate = firstNonNull(line, ['rate', 'unit_rate']);
  final gst = firstNonNull(line, ['gst']);
  return [
    if (qty != null) 'Qty $qty',
    if (rate != null) 'Rate $rate',
    if (gst != null) 'GST $gst',
  ].join(' · ');
}

Future<void> attachCatalogItemNames(
  List<Map<String, dynamic>> lines,
  Future<Map<String, dynamic>> Function(String id) fetchById,
) async {
  for (final line in lines) {
    if (itemLabel(line, fallback: '').isNotEmpty) continue;
    final id = mongoId(line['item_id'] ?? line['item']);
    if (id == null) continue;
    try {
      final catalog = await fetchById(id);
      final name = _readableName(catalog['item_name']);
      if (name != null) line['item_name'] = name;
    } catch (_) {}
  }
}

Future<void> resolveDocItemNames(
  Map<String, dynamic> doc,
  Future<Map<String, dynamic>> Function(String id) fetchById,
) async {
  await attachCatalogItemNames(lineItemsOf(doc), fetchById);
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
