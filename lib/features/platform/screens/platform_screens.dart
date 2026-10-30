import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../app/app_services.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/push_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await context.read<AppServices>().notifications.list({'page': 1, 'limit': 50});
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
        _error = null;
      });
      context.read<PushNotificationService>().refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _openNotification(Map<String, dynamic> row) {
    context.push(notificationRouteFor(row));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<AppServices>().notifications.markAllRead();
              _load();
            },
            child: const Text('Mark all read', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          const PushAlertsCard(),
          Expanded(
            child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : _error != null
                ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                : _items.isEmpty
                    ? EmptyListBody(message: 'No notifications')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          final unread = row['read'] != true && row['isRead'] != true;
                          final body = row['body']?.toString() ?? row['message']?.toString();
                          return ListTile(
                            leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none),
                            title: Text(row['title']?.toString() ?? body ?? 'Notification'),
                            subtitle: Text(
                              [
                                if (body != null && row['title'] != null) body,
                                formatDateTime(row['createdAt'] ?? row['created_at']),
                              ].where((e) => e.isNotEmpty).join(' · '),
                            ),
                            onTap: () async {
                              final id = idOf(row);
                              if (id != null) {
                                await context.read<AppServices>().notifications.markRead(id);
                              }
                              _openNotification(row);
                              _load();
                            },
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class PushAlertsCard extends StatelessWidget {
  const PushAlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushNotificationService>();
    final blocked = push.mobileSupported && push.enabled && !push.permissionGranted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_rounded, color: AppTheme.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Push notifications', style: AppTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          push.mobileSupported
                              ? 'Tasks, approvals, orders, inventory, and reports.'
                              : 'Phone alerts are available on the Android and iOS app.',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: push.enabled && push.mobileSupported,
                    onChanged: push.mobileSupported
                        ? (value) => push.setEnabled(value)
                        : null,
                  ),
                ],
              ),
              if (blocked)
                const Padding(
                  padding: EdgeInsets.only(left: 34, right: 8, bottom: 8),
                  child: Text(
                    'Notifications are blocked. Allow them for BldTrack in system settings, then turn this on again.',
                    style: TextStyle(color: AppTheme.danger, fontSize: 12, height: 1.3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppServices>().billing;
      final plans = await api.plans();
      Map<String, dynamic>? current;
      try {
        current = await api.currentSubscription();
      } catch (_) {}
      final pays = await api.payments({'page': 1, 'limit': 20});
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _current = current;
        _payments = pays.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & payments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.formPadding,
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : ListView(
                  padding: AppTheme.formPadding,
                  children: [
                    if (_current != null) ...[
                      const Text('Current plan', style: TextStyle(fontWeight: FontWeight.w700)),
                      Card(
                        child: ListTile(
                          title: Text(_current!['plan']?['name']?.toString() ?? labelOf(_current)),
                          subtitle: Text(_current!['status']?.toString() ?? ''),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text('Available plans', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final p in _plans)
                      Card(
                        child: ListTile(
                          title: Text(p['name']?.toString() ?? 'Plan'),
                          subtitle: Text(planPriceLabel(p)),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text('Payments', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final p in _payments)
                      ListTile(
                        title: Text('${p['amount'] ?? p['total'] ?? ''}'),
                        subtitle: Text(formatDateTime(p['createdAt'])),
                        trailing: StatusChip(status: p['status']?.toString()),
                      ),
                  ],
                ),
    );
  }
}
