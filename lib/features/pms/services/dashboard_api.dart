import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class DashboardApi {
  DashboardApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> overview([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dashboard/overview',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> procurement([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dashboard/procurement',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> pmsOverview({String? siteId}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dashboard/pms',
      queryParameters: {
        if (siteId != null && siteId.isNotEmpty) 'site_id': siteId,
      },
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> pmsProject(String projectId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/dashboard/pms/projects/$projectId',
    );
    return unwrapDataMap(res.data);
  }
}
