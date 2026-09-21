import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class MastersApi {
  MastersApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listSites({
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/sites',
      queryParameters: {
        'page': page,
        'limit': limit,
        'sortBy': 'site_name',
        'sortOrder': 'asc',
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listUsers({
    String? search,
    int page = 1,
    int limit = 100,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/users',
      queryParameters: {
        'page': page,
        'limit': limit,
        'sortBy': 'name',
        'sortOrder': 'asc',
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>?> getCurrentOrganization() async {
    final res = await _client.get<Map<String, dynamic>>('/organizations/current');
    final data = unwrapDataMap(res.data);
    if (data.isEmpty) return null;
    return data;
  }
}
