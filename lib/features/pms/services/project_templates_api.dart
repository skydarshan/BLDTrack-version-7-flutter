import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class ProjectTemplatesApi {
  ProjectTemplatesApi(this._client);

  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/project-templates',
      queryParameters: _clean(params),
    );
    return PaginatedResult(
      items: unwrapDataList(res.data)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/project-templates/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/project-templates',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/project-templates/$id',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('/project-templates/$id');

  Future<Map<String, dynamic>> createProject(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/project-templates/$id/create-project',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> apply(String id, Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/project-templates/$id/apply',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> clone(
    String id, [
    Map<String, dynamic> data = const {},
  ]) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/project-templates/$id/clone',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> restore(String id) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/project-templates/$id/restore',
      data: const {},
    );
    return unwrapDataMap(res.data);
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? params) {
    if (params == null) return null;
    final out = <String, dynamic>{};
    params.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v;
    });
    return out.isEmpty ? null : out;
  }
}
