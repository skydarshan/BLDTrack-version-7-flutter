import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class RequisitionRequestsApi {
  RequisitionRequestsApi(this._client);
  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> statusCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests/status-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approverInboxCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests/approver-inbox-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> pendingFirst([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests/pending-first-approval',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<PaginatedResult> pendingSecond([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests/pending-second-approval',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/requisition-requests/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> getDetail(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/requisition-requests/$id/detail');
    return unwrapDataMap(res.data);
  }

  /// Approval rows are `histories`. File downloads are `file_histories`.
  Future<({List<Map<String, dynamic>> histories, List<Map<String, dynamic>> fileHistories})>
      getHistory(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/requisition-requests/$id/history');
    final data = unwrapDataMap(res.data);
    List<Map<String, dynamic>> read(String key) {
      final raw = data[key];
      if (raw is! List) return const [];
      return asMapList(raw);
    }

    final fileHistories = read('file_histories');
    return (
      histories: read('histories'),
      fileHistories: fileHistories.isNotEmpty ? fileHistories : read('fileHistories'),
    );
  }

  Future<int?> getNextNumber(String site) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-requests/next-requisition-number',
      queryParameters: {'site': site},
    );
    final data = unwrapDataMap(res.data);
    final raw = firstNonNull(data, [
      'next_requisition_request_number',
      'requisition_request_number',
      'next',
      'number',
    ]);
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString().trim() ?? '');
  }

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data, {
    List<MapEntry<String, MultipartFileEntry>> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>('/requisition-requests', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/requisition-requests',
      payload: data,
      extraFiles: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> data, {
    List<MapEntry<String, MultipartFileEntry>> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.put<Map<String, dynamic>>('/requisition-requests/$id', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/requisition-requests/$id',
      payload: data,
      extraFiles: files,
      put: true,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> superEdit(
    String id,
    Map<String, dynamic> data, {
    List<MapEntry<String, MultipartFileEntry>> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.put<Map<String, dynamic>>(
        '/requisition-requests/$id/super-edit',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postNamedMultipart<Map<String, dynamic>>(
      '/requisition-requests/$id/super-edit',
      payload: data,
      extraFiles: files,
      put: true,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateStatus(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/requisition-requests/$id/status',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('/requisition-requests/$id');

  Future<List<int>> downloadPdf(String id) =>
      _client.downloadBytes('/requisition-requests/$id/pdf');

  Future<List<int>> downloadDocumentsZip(String id) =>
      _client.downloadBytes('/requisition-requests/$id/documents-zip');
}

class RateComparativesApi {
  RateComparativesApi(this._client);
  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> inboxCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/inbox-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approverInboxCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/approver-inbox-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> pendingFirst([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/pending-first-approval',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<PaginatedResult> pendingSecond([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/pending-second-approval',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/rate-comparatives/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateStatus(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/rate-comparatives/$id/status',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/rate-comparatives/$id', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateDraft(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/rate-comparatives/$id/draft', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> revise(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/rate-comparatives/$id/revise', data: data);
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> requisitionTitles([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/requisition-titles',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<List<Map<String, dynamic>>> bySitePurchaseCategory([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/rate-comparatives/by-site-purchase-category',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> merge(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/rate-comparatives/merge', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> split(String id, Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/rate-comparatives/$id/split', data: data);
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) => _client.delete<Map<String, dynamic>>('/rate-comparatives/$id');

  Future<Map<String, dynamic>> analyze(String id, {bool refresh = false}) async {
    final path = refresh
        ? '/ai/rate-comparatives/$id/analyze/refresh'
        : '/ai/rate-comparatives/$id/analyze';
    final res = await _client.post<Map<String, dynamic>>(path);
    return unwrapDataMap(res.data);
  }

  Future<List<int>> downloadPdf(String id) =>
      _client.downloadBytes('/rate-comparatives/$id/pdf');

  Future<List<int>> downloadVendorQuotationsZip(String id) =>
      _client.downloadBytes('/rate-comparatives/$id/vendor-quotations-zip');

  Future<Map<String, dynamic>> vendorScorecard(String vendorId) async {
    final res = await _client.get<Map<String, dynamic>>('/ai/vendors/$vendorId/scorecard');
    return unwrapDataMap(res.data);
  }

  /// Saves a comparative. Quotation files use `vendors_total_<index>_vendor_quotation`.
  Future<Map<String, dynamic>> saveForm(
    String path,
    Map<String, dynamic> data, {
    Map<String, MultipartFileEntry> files = const {},
  }) async {
    final res = files.isEmpty
        ? await _client.put<Map<String, dynamic>>(path, data: data)
        : await _client.postNamedMultipart<Map<String, dynamic>>(
            path,
            payload: data,
            namedFiles: files,
            put: true,
          );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> extractQuotation(
    String id, {
    String? vendorId,
    MultipartFileEntry? file,
    String? fileUrl,
  }) async {
    if (file != null) {
      final res = await _client.postNamedMultipart<Map<String, dynamic>>(
        '/ai/rate-comparatives/$id/extract-quotation',
        fields: {
          if (vendorId != null && vendorId.isNotEmpty) 'vendor_id': vendorId,
        },
        namedFiles: {'quotation': file},
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.post<Map<String, dynamic>>(
      '/ai/rate-comparatives/$id/extract-quotation',
      data: {
        if (vendorId != null && vendorId.isNotEmpty) 'vendor_id': vendorId,
        if (fileUrl != null && fileUrl.isNotEmpty) 'file_url': fileUrl,
      },
    );
    return unwrapDataMap(res.data);
  }
}

class RequisitionOrdersApi {
  RequisitionOrdersApi(this._client);
  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> statusCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders/status-counts',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/requisition-orders/$id');
    final doc = unwrapDataMap(res.data);
    final root = res.data;
    if (root != null) {
      doc['_rejectPO'] = root['rejectPO'] == true;
      doc['_canRevise'] = root['revision'] != false;
    }
    return doc;
  }

  Future<Map<String, dynamic>> nextNumber([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders/next-purchase-order-number',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> merge(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/requisition-orders/merge', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> revise(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/requisition-orders/$id/revise', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> reject(String id) async {
    final res = await _client.put<Map<String, dynamic>>('/requisition-orders/$id/reject');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approval(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/requisition-orders/$id/approval',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('/requisition-orders/$id', data: data);
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('/requisition-orders/$id');

  Future<List<Map<String, dynamic>>> uniqueVendors([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders/unique-vendors',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<List<Map<String, dynamic>>> pendingByVendor([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders/pending-by-vendor',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<List<Map<String, dynamic>>> approvedByVendor([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requisition-orders/approved-by-vendor',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<List<int>> downloadRo(String id, {dynamic revision}) =>
      _client.downloadBytes(
        '/requisition-orders/$id/download-ro',
        queryParameters: cleanQuery({'revision': revision}),
      );
}
