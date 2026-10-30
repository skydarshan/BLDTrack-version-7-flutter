import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

/// Project structure endpoints under `/projects/:id/structure`.
class StructureApi {
  StructureApi(this._client);

  final ApiClient _client;

  /// GET /projects/:id/structure/progress
  ///
  /// [includeModel] is true on first load. Colour refreshes omit it.
  Future<Map<String, dynamic>> progress(
    String projectId, {
    bool includeModel = false,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId/structure/progress',
      queryParameters: {
        if (includeModel) 'include_model': true,
      },
    );
    return unwrapDataMap(res.data);
  }

  /// GET /projects/:id/structure/:nodeId/tasks
  Future<Map<String, dynamic>> nodeTasks(String projectId, String nodeId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId/structure/$nodeId/tasks',
    );
    return unwrapDataMap(res.data);
  }

  /// GET /projects/:id/structure
  ///
  /// The default body is a nested `tree`. [flat] is the picker list
  /// (`?flat=true`), in depth-first display order, with ready-made labels.
  /// [types] is only sent in flat mode (`type=floor,unit`).
  Future<Map<String, dynamic>> tree(
    String projectId, {
    bool flat = false,
    List<String> types = const [],
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId/structure',
      queryParameters: {
        if (flat) 'flat': true,
        if (flat && types.isNotEmpty) 'type': types.join(','),
      },
    );
    return unwrapDataMap(res.data);
  }

  /// GET /projects/:id/structure/resolve
  ///
  /// Quick picks such as floors 3–7 or every 2BHK on one floor.
  /// Group the returned nodes by `parent`.
  Future<Map<String, dynamic>> resolve(
    String projectId, {
    required List<String> types,
    String? buildingId,
    String? floorId,
    int? fromLevel,
    int? toLevel,
    String? category,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId/structure/resolve',
      queryParameters: {
        'type': types.join(','),
        'building': ?_queryText(buildingId),
        'floor': ?_queryText(floorId),
        'from_level': ?fromLevel,
        'to_level': ?toLevel,
        'category': ?_queryText(category),
      },
    );
    return unwrapDataMap(res.data);
  }

  /// POST /projects/:id/structure/generate
  ///
  /// [preview] true returns the plan only. [preview] false writes the tower.
  /// A preview with `clashes` must be changed and previewed again before create.
  /// Create-time clashes come back as 409 `details`.
  Future<Map<String, dynamic>> generateTower(
    String projectId,
    Map<String, dynamic> data, {
    bool preview = true,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/structure/generate',
      data: {
        ...data,
        'preview': preview,
      },
    );
    return unwrapDataMap(res.data);
  }

  /// POST /projects/:id/structure/from-tasks
  Future<Map<String, dynamic>> fromTasks(String projectId) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/structure/from-tasks',
    );
    return unwrapDataMap(res.data);
  }

  /// GET /projects/:id/structure/model
  Future<Map<String, dynamic>> model(String projectId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId/structure/model',
    );
    return unwrapDataMap(res.data);
  }

  /// POST /projects/:id/structure. Do not send `site`.
  Future<Map<String, dynamic>> createNode(
    String projectId,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/structure',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  /// PATCH /projects/:id/structure/:nodeId. Send only fields that change.
  Future<Map<String, dynamic>> updateNode(
    String projectId,
    String nodeId,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/projects/$projectId/structure/$nodeId',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  /// DELETE /structure/:nodeId
  ///
  /// A 409 names `cascade` or `unlink_tasks` in `details[].field`. Confirm,
  /// then retry with that flag. Tasks are unlinked, never deleted.
  /// Success is `{ deleted_nodes, unlinked_tasks }`.
  Future<Map<String, dynamic>> deleteNode(
    String projectId,
    String nodeId, {
    bool cascade = false,
    bool unlinkTasks = false,
  }) async {
    final res = await _client.delete<Map<String, dynamic>>(
      '/projects/$projectId/structure/$nodeId',
      queryParameters: {
        if (cascade) 'cascade': true,
        if (unlinkTasks) 'unlink_tasks': true,
      },
    );
    return unwrapDataMap(res.data);
  }

  /// POST /structure/reorder. [parentId] is null for the top level.
  ///
  /// Listed nodes go first. Every id must be a direct child of [parentId].
  Future<Map<String, dynamic>> reorder(
    String projectId, {
    required String? parentId,
    required List<String> nodeIds,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/structure/reorder',
      data: {
        'parent': parentId,
        'node_ids': nodeIds,
      },
    );
    return unwrapDataMap(res.data);
  }
}

String? _queryText(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  return text;
}
