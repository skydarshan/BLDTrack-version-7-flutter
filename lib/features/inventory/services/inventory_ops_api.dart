import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class InventoryOpsApi {
  InventoryOpsApi(this._client);
  final ApiClient _client;

  Future<PaginatedResult> statistics([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inventory-statistics/in-out-by-item',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> itemStatistics(String itemId, [Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inventory-statistics/item/$itemId',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<List<int>> exportStatistics([Map<String, dynamic>? params]) =>
      _client.downloadBytes(
        '/inventory-statistics/in-out-by-item/export',
        queryParameters: cleanQuery(params),
      );

  Future<PaginatedResult> ins([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inventory-ins',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<PaginatedResult> outs([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inventory-outs',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<List<Map<String, dynamic>>> availableStock([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inventory-ins/available-stock',
      queryParameters: cleanQuery(params),
    );
    return asMapList(unwrapDataList(res.data));
  }

  Future<PaginatedResult> listImr([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/material-issue-records',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getImr(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/material-issue-records/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> nextSlipNumber(String siteId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/material-issue-records/next-slip-number',
      queryParameters: {'site_id': siteId},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createImr(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/material-issue-records', data: data);
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> listTransfers([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/inter-site-transfers',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getTransfer(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/inter-site-transfers/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createTransfer(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/inter-site-transfers', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> dispatchTransfer(String id, Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/inter-site-transfers/$id/dispatch',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> receiveTransfer(String id, Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/inter-site-transfers/$id/receive',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> listScrap([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/scrapes',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getScrap(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/scrapes/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> nextScrapNumber(String siteId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/scrapes/next-scrap-number',
      queryParameters: {'site_id': siteId},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> createScrap(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/scrapes', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approveScrap(String id, Map<String, dynamic> data) async {
    final res = await _client.patch<Map<String, dynamic>>('/scrapes/$id/approval', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> closeScrap(String id, [Map<String, dynamic> data = const {}]) async {
    final res = await _client.patch<Map<String, dynamic>>('/scrapes/$id/close', data: data);
    return unwrapDataMap(res.data);
  }
}
