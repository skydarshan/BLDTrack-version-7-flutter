import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';
import '../../pms/services/projects_api.dart';

/// Generic REST CRUD for `/api/v1/{resource}` masters.
class MasterResourceApi {
  MasterResourceApi(this._client, this.resourcePath);

  final ApiClient _client;
  final String resourcePath;

  Future<PaginatedResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      resourcePath,
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
    final res = await _client.get<Map<String, dynamic>>('$resourcePath/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>(resourcePath, data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>('$resourcePath/$id', data: data);
    return unwrapDataMap(res.data);
  }

  Future<void> delete(String id) =>
      _client.delete<Map<String, dynamic>>('$resourcePath/$id');

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

class SettingsApis {
  SettingsApis(ApiClient client)
      : users = MasterResourceApi(client, '/users'),
        roles = MasterResourceApi(client, '/roles'),
        locations = MasterResourceApi(client, '/locations'),
        companies = MasterResourceApi(client, '/companies'),
        sites = MasterResourceApi(client, '/sites'),
        siteStaff = MasterResourceApi(client, '/site-staff'),
        contractors = MasterResourceApi(client, '/contractors'),
        activities = MasterResourceApi(client, '/activities'),
        subActivities = MasterResourceApi(client, '/sub-activities'),
        uoms = MasterResourceApi(client, '/uoms'),
        gsts = MasterResourceApi(client, '/gsts'),
        brands = MasterResourceApi(client, '/brands'),
        categories = MasterResourceApi(client, '/categories'),
        subCategories = MasterResourceApi(client, '/sub-categories'),
        vendors = MasterResourceApi(client, '/vendors'),
        items = MasterResourceApi(client, '/items'),
        miscConfigs = MasterResourceApi(client, '/miscellaneous-configs'),
        auditLogs = MasterResourceApi(client, '/audit-logs'),
        _client = client;

  final ApiClient _client;
  final MasterResourceApi users;
  final MasterResourceApi roles;
  final MasterResourceApi locations;
  final MasterResourceApi companies;
  final MasterResourceApi sites;
  final MasterResourceApi siteStaff;
  final MasterResourceApi contractors;
  final MasterResourceApi activities;
  final MasterResourceApi subActivities;
  final MasterResourceApi uoms;
  final MasterResourceApi gsts;
  final MasterResourceApi brands;
  final MasterResourceApi categories;
  final MasterResourceApi subCategories;
  final MasterResourceApi vendors;
  final MasterResourceApi items;
  final MasterResourceApi miscConfigs;
  final MasterResourceApi auditLogs;

  Future<Map<String, dynamic>?> getOrganization() async {
    final res = await _client.get<Map<String, dynamic>>('/organizations/current');
    final data = unwrapDataMap(res.data);
    return data.isEmpty ? null : data;
  }

  Future<Map<String, dynamic>> updateOrganization(Map<String, dynamic> data) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/organizations/current',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> listModules() async {
    final res = await _client.get<Map<String, dynamic>>('/modules');
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listPermissionDefs() async {
    final res = await _client.get<Map<String, dynamic>>('/permissions');
    return unwrapDataList(res.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>?> getNotificationEmail() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/organizations/current/notification-email',
    );
    final data = unwrapDataMap(res.data);
    return data.isEmpty ? null : data;
  }

  Future<Map<String, dynamic>> updateNotificationEmail(
    Map<String, dynamic> data,
  ) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/organizations/current/notification-email',
      data: data,
    );
    return unwrapDataMap(res.data);
  }

  Future<void> verifyNotificationEmail() =>
      _client.post<Map<String, dynamic>>(
        '/organizations/current/notification-email/verify',
        data: const {},
      );

  Future<void> testNotificationEmail() =>
      _client.post<Map<String, dynamic>>(
        '/organizations/current/notification-email/test',
        data: const {},
      );

  /// GET /items/:id/uom-options — allowed UOMs for procurement lines.
  Future<List<Map<String, dynamic>>> getItemUomOptions(String itemId) async {
    final res = await _client.get<Map<String, dynamic>>('/items/$itemId/uom-options');
    return asMapList(unwrapDataList(res.data));
  }

  /// POST /items/:id/convert-uom — backend conversion math.
  Future<Map<String, dynamic>> convertItemUom(
    String itemId, {
    required String fromUom,
    required String toUom,
    required num qty,
    num? rate,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/items/$itemId/convert-uom',
      data: {
        'from_uom': fromUom,
        'to_uom': toUom,
        'qty': qty,
        'rate': ?rate,
      },
    );
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> auditLogStats([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/audit-logs/stats',
      queryParameters: cleanQuery(params),
    );
    return unwrapDataMap(res.data);
  }
}
