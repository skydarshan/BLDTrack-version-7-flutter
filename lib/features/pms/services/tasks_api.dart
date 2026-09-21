import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';
import 'projects_api.dart';

class TasksApi {
  TasksApi(this._client);

  final ApiClient _client;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks',
      queryParameters: _clean(params),
    );
    return PaginatedResult(
      items: _asMaps(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<PaginatedResult> myTasks([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/my',
      queryParameters: _clean(params),
    );
    return PaginatedResult(
      items: _asMaps(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> statusCounts([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/status-counts',
      queryParameters: _clean(params),
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> board({required String projectId}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/board',
      queryParameters: {'project': projectId},
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> pendingApprovals([
    Map<String, dynamic>? params,
  ]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/approvals/pending',
      queryParameters: _clean(params),
    );
    return _asMaps(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/tasks/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>('/tasks', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks',
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
      final res = await _client.put<Map<String, dynamic>>('/tasks/$id', data: data);
      return unwrapDataMap(res.data);
    }
    final res = await _client.putMultipart<Map<String, dynamic>>(
      '/tasks/$id',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateAssignment(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/tasks/$id/assignment',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('/tasks/$id');

  Future<void> removeMedia(String id, Map<String, dynamic> body) =>
      _client.delete<Map<String, dynamic>>('/tasks/$id/media', data: body);

  Future<Map<String, dynamic>> submitProgress(
    String id,
    Map<String, dynamic> data, {
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/progress',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/progress',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<PaginatedResult> getProgress(
    String id, {
    int page = 1,
    int limit = 50,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/$id/progress',
      queryParameters: {'page': page, 'limit': limit},
    );
    return PaginatedResult(
      items: _asMaps(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> markComplete(
    String id, {
    Map<String, dynamic> data = const {},
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/complete',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/complete',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> approveCompletion(
    String id, {
    Map<String, dynamic> data = const {},
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/complete/approve',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/complete/approve',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> reviseCompletion(
    String id, {
    required Map<String, dynamic> data,
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/complete/revise',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/complete/revise',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  /// Step 1 revise from ready queue (remarks required).
  Future<Map<String, dynamic>> reviseReadyCompletion(
    String id, {
    required Map<String, dynamic> data,
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/complete/revise-request',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/complete/revise-request',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  /// After Step 1 revise — assignee resubmits for approval.
  Future<Map<String, dynamic>> resubmitCompletion(
    String id, {
    Map<String, dynamic> data = const {},
    List<MultipartFileEntry> files = const [],
  }) async {
    if (files.isEmpty) {
      final res = await _client.post<Map<String, dynamic>>(
        '/tasks/$id/complete/resubmit',
        data: data,
      );
      return unwrapDataMap(res.data);
    }
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/complete/resubmit',
      payload: data,
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> addMedia(
    String id, {
    List<MultipartFileEntry> files = const [],
    Map<String, dynamic>? payload,
  }) async {
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/tasks/$id/media',
      payload: payload ?? const {},
      files: files,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> listComments(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/tasks/$id/comments');
    return _asMaps(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> addComment(String id, Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/tasks/$id/comments', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> updateComment(
    String taskId,
    String commentId,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/tasks/$taskId/comments/$commentId',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> deleteComment(String taskId, String commentId) =>
      _client.delete<Map<String, dynamic>>('/tasks/$taskId/comments/$commentId');

  Future<PaginatedResult> readyForCompletion([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/tasks/completions/ready',
      queryParameters: _clean(params),
    );
    return PaginatedResult(
      items: _asMaps(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  List<Map<String, dynamic>> _asMaps(List<dynamic> list) => list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

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
