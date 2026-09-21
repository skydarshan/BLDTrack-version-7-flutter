import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

export '../../../core/network/api_helpers.dart' show PaginatedResult;

class ProjectsApi {
  ProjectsApi(this._client);

  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects',
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

  Future<Map<String, dynamic>> statusCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/status-counts',
      queryParameters: _clean(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/projects/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>('/projects', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/projects',
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
      final res = await _client.put<Map<String, dynamic>>('/projects/$id', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.putMultipart<Map<String, dynamic>>(
      '/projects/$id',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> archive(String id) =>
      _client.post<Map<String, dynamic>>('/projects/$id/archive');

  Future<void> unarchive(String id) =>
      _client.post<Map<String, dynamic>>('/projects/$id/unarchive');

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('/projects/$id');

  Future<void> removeMedia(String id, Map<String, dynamic> body) =>
      _client.delete<Map<String, dynamic>>('/projects/$id/media', data: body);

  Future<Map<String, dynamic>> saveAsTemplate(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$id/save-as-template',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> getTaskTree(
    String id, {
    String? status,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$id/tasks/tree',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final data = res.data?['data'];
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      for (final key in ['tree', 'roots']) {
        final list = data[key];
        if (list is List) {
          return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> listComments(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/projects/$id/comments');
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> addComment(String id, Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/projects/$id/comments', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateComment(
    String projectId,
    String commentId,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/projects/$projectId/comments/$commentId',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> deleteComment(String projectId, String commentId) =>
      _client.delete<Map<String, dynamic>>('/projects/$projectId/comments/$commentId');

  Future<Map<String, dynamic>> addMedia(
    String id, {
    List<MultipartFileEntry> files = const [],
    Map<String, dynamic>? payload,
  }) async {
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/projects/$id/media',
      payload: payload ?? const {},
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> getAudit(
    String id, {
    int page = 1,
    int limit = 50,
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$id/audit',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
      },
    );
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getTaskTimeline(String id) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$id/tasks/timeline',
    );
    return unwrapDataMap(res.data);
  }

  Future<List<int>> exportTasks(String id) =>
      _client.downloadBytes('/projects/$id/tasks/export');

  Future<List<int>> downloadImportTemplate(String id) =>
      _client.downloadBytes('/projects/$id/tasks/import/template');

  Future<Map<String, dynamic>> importFile(
    String id,
    MultipartFileEntry file, {
    bool dryRun = true,
  }) async {
    final res = await _client.postFileField<Map<String, dynamic>>(
      '/projects/$id/tasks/import/file',
      file: file,
      queryParameters: {'dryRun': dryRun},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> importJson(
    String id,
    Map<String, dynamic> data, {
    bool dryRun = true,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$id/tasks/import',
      data: data,
      queryParameters: {'dryRun': dryRun},
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> commitImport(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$id/tasks/import/commit',
      data: data,
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
