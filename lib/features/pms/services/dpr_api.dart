import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class DprDetail {
  const DprDetail({required this.report, this.history = const []});

  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> history;
}

class DprApi {
  DprApi(this._client);

  final ApiClient _client;
  static const _base = '/daily-progress-reports';

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      _base,
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<DprDetail> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('$_base/$id');
    final root = res.data ?? const <String, dynamic>{};
    final meta = root['meta'];
    final historyRaw = meta is Map
        ? meta['history']
        : root['history'];
    return DprDetail(
      report: unwrapDataMap(root),
      history: asMapList(historyRaw is List ? historyRaw : const []),
    );
  }

  Future<Map<String, dynamic>> getForDate({
    required String siteId,
    String? date,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '$_base/today',
      queryParameters: cleanQuery({
        'site': siteId,
        'date': date,
      }),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(_base, data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      _base,
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.put<Map<String, dynamic>>('$_base/$id', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.putMultipart<Map<String, dynamic>>(
      '$_base/$id',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('$_base/$id');

  Future<Map<String, dynamic>> submit(
    String id,
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '$_base/$id/submit',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '$_base/$id/submit',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approve(String id, {String? remarks}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '$_base/$id/approve',
      data: {'remarks': remarks ?? ''},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> revise(String id, {required String remarks}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '$_base/$id/revise',
      data: {'remarks': remarks},
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> pendingApprovals([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '$_base/approvals/pending',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> missing({String? date}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '$_base/missing',
      queryParameters: cleanQuery({'date': date}),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> remindMissing({String? date}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '$_base/missing/remind',
      data: {if (date != null && date.isNotEmpty) 'date': date},
    );
    return unwrapDataMap(res.data);
  }

  Future<({Map<String, dynamic> report, String message, bool applied, int entryCount})>
      prefillWorkSummary(
    String id, {
    bool replace = false,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '$_base/$id/prefill-work-summary',
      data: {'replace': replace},
    );
    final root = res.data ?? const <String, dynamic>{};
    final meta = root['meta'] is Map ? Map<String, dynamic>.from(root['meta'] as Map) : const <String, dynamic>{};
    final appliedFlag = root.containsKey('applied') ? root['applied'] : meta['applied'];
    final countRaw = root['entry_count'] ?? meta['entry_count'];
    return (
      report: unwrapDataMap(root),
      message: root['message']?.toString() ?? '',
      applied: appliedFlag != false,
      entryCount: countRaw is num ? countRaw.toInt() : 0,
    );
  }

  Future<Map<String, dynamic>> removeMedia(
    String id, {
    required String type,
    required String url,
  }) async {
    final res = await _client.delete<Map<String, dynamic>>(
      '$_base/$id/media',
      data: {'type': type, 'url': url},
    );
    return unwrapDataMap(res.data);
  }

  Future<List<int>> exportPdf(String id) =>
      _client.downloadBytes('$_base/$id/pdf');
}
