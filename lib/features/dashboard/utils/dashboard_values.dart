import 'package:intl/intl.dart';

import '../../../core/network/api_helpers.dart';

/// First of the current month through today, as `yyyy-MM-dd`.
({String dateFrom, String dateTo}) defaultDashboardDateRange([DateTime? now]) {
  final clock = now ?? DateTime.now();
  return (
    dateFrom: isoYmd(DateTime(clock.year, clock.month, 1)),
    dateTo: isoYmd(clock),
  );
}

String isoYmd(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String formatDisplayDate(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '—';
  final raw = iso.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  final DateTime? date;
  if (match != null) {
    date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  } else {
    date = DateTime.tryParse(raw);
  }
  if (date == null) return raw;
  return DateFormat('dd MMM yyyy').format(date);
}

String formatGeneratedAt(DateTime when) {
  return DateFormat('dd MMM yyyy, HH:mm').format(when.toLocal());
}

String sanitizePdfText(Object? value) {
  return '${value ?? ''}'
      .replaceAll('\u20B9', 'Rs.')
      .replaceAll(RegExp(r'[\u00A0\u202F\u2009\u2007\uFEFF]'), '')
      .replaceAll('—', '-')
      .replaceAll('…', '...')
      .trim();
}

String formatIndianDigits(num amount, int fractionDigits) {
  if (amount.isNaN || amount.isInfinite) return '0';
  final negative = amount < 0;
  final abs = amount.abs();
  final fixed = fractionDigits > 0
      ? abs.toStringAsFixed(fractionDigits)
      : abs.round().toString();
  final parts = fixed.split('.');
  var intPart = parts.first;
  final decPart = parts.length > 1 ? parts[1] : null;
  if (intPart.length > 3) {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    intPart = '${groups.join(',')},$last3';
  }
  final body = decPart != null && fractionDigits > 0
      ? '$intPart.$decPart'
      : intPart;
  return negative ? '-$body' : body;
}

String formatPdfInr(num? value) {
  final amount = value ?? 0;
  if (amount.isNaN) return 'Rs. 0.00';
  return 'Rs. ${formatIndianDigits(amount, 2)}';
}

String formatPdfCompactInr(num? value) {
  final amount = value ?? 0;
  if (amount.isNaN) return 'Rs. 0';
  final abs = amount.abs();
  if (abs >= 1e7) return 'Rs. ${formatIndianDigits(amount / 1e7, 2)} Cr';
  if (abs >= 1e5) return 'Rs. ${formatIndianDigits(amount / 1e5, 2)} L';
  return 'Rs. ${formatIndianDigits(amount, 0)}';
}

String formatFullInr(num? value) {
  final amount = value ?? 0;
  if (amount.isNaN) return '₹0.00';
  return '₹${formatIndianDigits(amount, 2)}';
}

/// Prefer a server-formatted rupee string when the API already sent one.
String formatCompactInr(num? value, [String? formattedValue]) {
  final formatted = formattedValue?.trim();
  if (formatted != null && formatted.startsWith('₹')) return formatted;
  final amount = value ?? 0;
  if (amount.isNaN) return '₹0';
  final abs = amount.abs();
  if (abs >= 1e7) return '₹${(amount / 1e7).toStringAsFixed(2)}Cr';
  if (abs >= 1e5) return '₹${(amount / 1e5).toStringAsFixed(2)}L';
  return '₹${formatIndianDigits(amount, 0)}';
}

double rupeesToLakhs(num? value) {
  final n = value ?? 0;
  if (n.isNaN) return 0;
  return n / 1e5;
}

class ChartYScale {
  const ChartYScale({required this.ticks, required this.max});

  final List<double> ticks;
  final double max;
}

/// Y-axis ticks for the procurement chart. Values are in lakhs.
ChartYScale buildChartYScale(double maxLakhs) {
  final rawMax = maxLakhs < 0.5 ? 0.5 : maxLakhs;
  final double step;
  if (rawMax <= 15) {
    step = 5;
  } else if (rawMax <= 60) {
    step = 15;
  } else if (rawMax <= 150) {
    step = 30;
  } else {
    step = (rawMax / 4 / 10).ceil() * 10;
  }
  final top = (rawMax / step).ceil() * step;
  final resolvedTop = top == 0 ? step : top.toDouble();
  final ticks = <double>[];
  for (var v = 0.0; v <= resolvedTop + 0.001; v += step) {
    ticks.add(v);
  }
  return ChartYScale(ticks: ticks, max: resolvedTop);
}

String siteCardLabel({required String name, String code = ''}) {
  final trimmedCode = code.trim();
  if (trimmedCode.isNotEmpty) return trimmedCode.toUpperCase();
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'SITE';
  if (trimmed.length <= 14) return trimmed.toUpperCase();
  return trimmed.substring(0, 14).toUpperCase();
}

class SitePrRow {
  const SitePrRow({
    required this.siteId,
    required this.siteName,
    required this.siteCode,
    required this.displayName,
    required this.prsRaised,
  });

  final String siteId;
  final String siteName;
  final String siteCode;
  final String displayName;
  final int prsRaised;
}

class DashboardOverview {
  const DashboardOverview({
    required this.inventoryValue,
    required this.inventoryFormatted,
    required this.trendPercent,
    required this.activeSites,
    required this.sitesStatus,
    required this.yetToReceive,
    required this.yetFormatted,
    required this.pendingLines,
    required this.prCount,
    required this.prPending,
    required this.prTrend,
    required this.sites,
  });

  final double inventoryValue;
  final String? inventoryFormatted;
  final double? trendPercent;
  final int activeSites;
  final String sitesStatus;
  final double yetToReceive;
  final String? yetFormatted;
  final int pendingLines;
  final int prCount;
  final int prPending;
  final double? prTrend;
  final List<SitePrRow> sites;

  static const empty = DashboardOverview(
    inventoryValue: 0,
    inventoryFormatted: null,
    trendPercent: null,
    activeSites: 0,
    sitesStatus: 'All Operational',
    yetToReceive: 0,
    yetFormatted: null,
    pendingLines: 0,
    prCount: 0,
    prPending: 0,
    prTrend: null,
    sites: [],
  );
}

class ProcurementBucket {
  const ProcurementBucket({
    required this.label,
    required this.key,
    required this.ordered,
    required this.received,
  });

  final String label;
  final String key;
  final double ordered;
  final double received;
}

class PurchasedMaterial {
  const PurchasedMaterial({
    required this.name,
    required this.orderedValue,
    required this.receivedValue,
  });

  final String name;
  final double orderedValue;
  final double receivedValue;

  /// On-screen bar uses received value, and falls back to ordered.
  double get displayValue =>
      receivedValue != 0 ? receivedValue : orderedValue;
}

class ProcurementOverview {
  const ProcurementOverview({
    required this.granularity,
    required this.buckets,
    required this.top,
    required this.least,
  });

  final String granularity;
  final List<ProcurementBucket> buckets;
  final List<PurchasedMaterial> top;
  final List<PurchasedMaterial> least;

  static const empty = ProcurementOverview(
    granularity: 'week',
    buckets: [],
    top: [],
    least: [],
  );

  ProcurementOverview copyWith({
    String? granularity,
    List<ProcurementBucket>? buckets,
  }) {
    return ProcurementOverview(
      granularity: granularity ?? this.granularity,
      buckets: buckets ?? this.buckets,
      top: top,
      least: least,
    );
  }
}

dynamic _pick(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

double _toDouble(dynamic value, [double fallback = 0]) {
  if (value == null || value == '') return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

double? _toOptionalDouble(dynamic value) {
  if (value == null || value == '') return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int _toInt(dynamic value, [int fallback = 0]) {
  if (value == null || value == '') return fallback;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String? _asText(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _root(Map<String, dynamic> raw) {
  final data = raw['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return raw;
}

SitePrRow? _siteRow(dynamic raw, int index) {
  if (raw is! Map) return null;
  final row = Map<String, dynamic>.from(raw);
  final siteId = idOf(_pick(row, ['site_id', 'siteId', '_id'])) ?? '';
  final siteCode = _asText(_pick(row, ['site_code', 'siteCode', 'code'])) ?? '';
  final siteName =
      _asText(_pick(row, ['site_name', 'siteName', 'name', 'label'])) ??
      (siteCode.isNotEmpty ? siteCode : 'Site ${index + 1}');
  return SitePrRow(
    siteId: siteId,
    siteName: siteName,
    siteCode: siteCode,
    displayName: siteCardLabel(name: siteName, code: siteCode),
    prsRaised: _toInt(
      _pick(row, ['prs_raised', 'prsRaised', 'pr_count', 'prCount', 'count', 'total']),
    ),
  );
}

DashboardOverview normalizeDashboardOverview(Map<String, dynamic> raw) {
  final data = _root(raw);
  final metrics = _pick(data, ['metrics', 'summary', 'overview']);
  final metricMap = metrics is Map ? Map<String, dynamic>.from(metrics) : data;

  Map<String, dynamic> block(List<String> keys) {
    final value = _pick(data, keys);
    if (value is Map) return Map<String, dynamic>.from(value);
    return metricMap;
  }

  final remaining = block([
    'remaining_inventory',
    'remainingInventory',
    'remaining_inventory_value',
  ]);
  final sitesBlock = block(['active_sites', 'activeSites']);
  final pending = block([
    'items_yet_to_receive',
    'itemsYetToReceive',
    'items_yet_to_be_received',
    'itemsYetToBeReceived',
    'pending_receipt',
  ]);
  final prs = block([
    'total_purchase_requests',
    'totalPurchaseRequests',
    'purchase_requests',
  ]);

  final siteList = _pick(data, [
    'site_wise_purchase_requests',
    'siteWisePurchaseRequests',
    'sites',
    'siteWisePr',
  ]);
  final sites = <SitePrRow>[];
  if (siteList is List) {
    for (var i = 0; i < siteList.length; i++) {
      final row = _siteRow(siteList[i], i);
      if (row != null) sites.add(row);
    }
  }

  return DashboardOverview(
    inventoryValue: _toDouble(
      _pick(remaining, [
        'value',
        'amount',
        'remaining_inventory_value',
        'remainingInventoryValue',
      ]),
    ),
    inventoryFormatted: _asText(
      _pick(remaining, [
        'value_formatted',
        'valueFormatted',
        'formatted_value',
        'formattedValue',
      ]),
    ),
    trendPercent: _toOptionalDouble(
      _pick(remaining, [
        'trend_percent',
        'trendPercent',
        'change_percent',
        'changePercent',
      ]),
    ),
    activeSites: _toInt(
      _pick(sitesBlock, ['count', 'active_sites_count', 'activeSitesCount', 'value']),
    ),
    sitesStatus:
        _asText(_pick(sitesBlock, ['status_label', 'statusLabel', 'label'])) ??
        'All Operational',
    yetToReceive: _toDouble(
      _pick(pending, [
        'value',
        'amount',
        'items_yet_to_be_received',
        'itemsYetToBeReceived',
      ]),
    ),
    yetFormatted: _asText(
      _pick(pending, [
        'value_formatted',
        'valueFormatted',
        'formatted_value',
        'formattedValue',
      ]),
    ),
    pendingLines: _toInt(
      _pick(pending, [
        'line_items_count',
        'lineItemsCount',
        'pending_line_items',
        'pendingLineItems',
        'line_items',
        'lineItems',
        'count',
      ]),
    ),
    prCount: _toInt(
      _pick(prs, ['count', 'total', 'total_purchase_requests', 'totalPurchaseRequests']),
    ),
    prPending: _toInt(_pick(prs, ['pending_count', 'pendingCount', 'pending'])),
    prTrend: _toOptionalDouble(
      _pick(prs, ['trend_delta', 'trendDelta', 'change', 'delta']),
    ),
    sites: sites,
  );
}

ProcurementOverview normalizeProcurementOverview(Map<String, dynamic> raw) {
  final data = _root(raw);
  final value = data['procurement_value'];
  final valueMap = value is Map ? Map<String, dynamic>.from(value) : const {};
  final bucketRaw = valueMap['buckets'];
  final buckets = <ProcurementBucket>[];
  if (bucketRaw is List) {
    for (final item in bucketRaw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final key = _asText(row['key']) ?? '';
      buckets.add(
        ProcurementBucket(
          label: _asText(row['label']) ?? (key.isEmpty ? '' : key),
          key: key,
          ordered: _toDouble(_pick(row, ['ordered', 'ordered_value'])),
          received: _toDouble(_pick(row, ['received', 'received_value'])),
        ),
      );
    }
  }

  List<PurchasedMaterial> materials(String key) {
    final list = data[key];
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map)
          PurchasedMaterial(
            name: _asText(Map<String, dynamic>.from(item)['item_name']) ?? '—',
            orderedValue: _toDouble(
              Map<String, dynamic>.from(item)['ordered_value'],
            ),
            receivedValue: _toDouble(
              Map<String, dynamic>.from(item)['received_value'],
            ),
          ),
    ];
  }

  return ProcurementOverview(
    granularity: _asText(valueMap['granularity']) ?? 'week',
    buckets: buckets,
    top: materials('top_purchased_materials'),
    least: materials('least_purchased_materials'),
  );
}

String _lookupKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Super admin sees API site rows. Everyone else sees their assigned sites,
/// with PR counts filled in from the overview payload.
List<SitePrRow> visibleSiteRows({
  required List<SitePrRow> apiRows,
  required bool unrestricted,
  required List<Map<String, dynamic>> assignedSites,
}) {
  if (unrestricted) return apiRows;

  final byId = <String, SitePrRow>{
    for (final row in apiRows)
      if (row.siteId.isNotEmpty) row.siteId: row,
  };
  final byName = <String, SitePrRow>{
    for (final row in apiRows) _lookupKey(row.siteName): row,
  };

  final rows = <SitePrRow>[];
  for (var i = 0; i < assignedSites.length; i++) {
    final site = assignedSites[i];
    final siteId = idOf(site) ?? '';
    final siteName =
        _asText(site['site_name']) ??
        _asText(site['name']) ??
        'Site ${i + 1}';
    final siteCode = _asText(site['site_code']) ?? _asText(site['code']) ?? '';
    final fromApi =
        byId[siteId] ??
        byName[_lookupKey(siteName)] ??
        (siteCode.isEmpty ? null : byName[_lookupKey(siteCode)]);
    rows.add(
      SitePrRow(
        siteId: siteId,
        siteName: siteName,
        siteCode: siteCode,
        displayName: siteCardLabel(name: siteName, code: siteCode),
        prsRaised: fromApi?.prsRaised ?? 0,
      ),
    );
  }
  return rows;
}
