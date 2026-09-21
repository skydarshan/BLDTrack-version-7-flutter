import '../../../core/network/api_client.dart';
import '../../../core/network/api_helpers.dart';

class NotificationsApi {
  NotificationsApi(this._client);
  final ApiClient _client;

  Future<NotificationListResult> list([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: cleanQuery(params),
    );
    return unwrapNotifications(res.data);
  }

  Future<int> unreadCount() async {
    final res = await _client.get<Map<String, dynamic>>('/notifications/unread-count');
    final data = unwrapDataMap(res.data);
    final count = data['unreadCount'] ?? data['count'] ?? data['unread'];
    if (count is num) return count.toInt();
    return 0;
  }

  Future<void> markRead(String id) =>
      _client.patch<Map<String, dynamic>>('/notifications/$id/read');

  Future<void> markAllRead() =>
      _client.post<Map<String, dynamic>>('/notifications/read-all', data: const {});
}

class BillingApi {
  BillingApi(this._client);
  final ApiClient _client;

  Future<List<Map<String, dynamic>>> plans() async {
    final res = await _client.get<Map<String, dynamic>>('/subscriptions/plans');
    return asMapList(unwrapDataList(res.data));
  }

  Future<Map<String, dynamic>> plan(String id) async {
    final res = await _client.get<Map<String, dynamic>>('/subscriptions/plans/$id');
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> currentSubscription() async {
    final res = await _client.get<Map<String, dynamic>>('/subscriptions/current');
    return unwrapDataMap(res.data);
  }

  Future<List<Map<String, dynamic>>> subscriptionHistory() async {
    final res = await _client.get<Map<String, dynamic>>('/subscriptions/history');
    return asMapList(unwrapDataList(res.data));
  }

  Future<PaginatedResult> payments([Map<String, dynamic>? params]) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/payments',
      queryParameters: cleanQuery(params),
    );
    return PaginatedResult(
      items: asMapList(unwrapDataList(res.data)),
      pagination: unwrapPagination(res.data),
    );
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/payments/create-order', data: data);
    return unwrapDataMap(res.data);
  }

  Future<Map<String, dynamic>> verifyPayment(Map<String, dynamic> data) async {
    final res = await _client.post<Map<String, dynamic>>('/payments/verify', data: data);
    return unwrapDataMap(res.data);
  }
}
