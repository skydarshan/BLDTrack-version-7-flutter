import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_helpers.dart';
import 'platform_apis.dart';

const _enabledKey = 'push_enabled';
const _seenKey = 'push_seen_ids';
const _channelId = 'bldtrack_alerts_v2';

@pragma('vm:entry-point')
void onBldTrackNotificationTap(NotificationResponse response) {
  PushNotificationService.rememberTap(response.payload);
}

/// Shows phone notifications for new in-app alerts and opens the related screen on tap.
class PushNotificationService extends ChangeNotifier with WidgetsBindingObserver {
  PushNotificationService(this._api) {
    instance = this;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPrefs());
  }

  static PushNotificationService? instance;
  static String? pendingPayload;

  final NotificationsApi _api;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _seen = <String>{};

  GoRouter? _router;
  Timer? _timer;
  bool _enabled = true;
  bool _prefsLoaded = false;
  bool _pluginReady = false;
  bool _polling = false;
  bool _watching = false;
  bool _permissionGranted = true;
  bool _disposed = false;
  Future<bool>? _permissionInFlight;
  int _unreadCount = 0;

  bool get enabled => _enabled;
  bool get permissionGranted => _permissionGranted;
  int get unreadCount => _unreadCount;

  bool get mobileSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static void rememberTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final service = instance;
    if (service == null) {
      pendingPayload = payload;
      return;
    }
    service.handleTap(payload);
  }

  void attachRouter(GoRouter router) {
    _router = router;
    _openPending();
  }

  Future<void> start() async {
    _watching = true;
    await _loadPrefs();
    if (!_enabled || _disposed) return;
    await _ensurePlugin();
    await _ensurePermission();
    _schedule();
    await refresh();
    _openPending();
  }

  void stop() {
    _watching = false;
    _timer?.cancel();
    _unreadCount = 0;
    pendingPayload = null;
    unawaited(_plugin.cancelAll());
    _notify();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    _notify();
    if (!_watching) return;
    if (!value) {
      _timer?.cancel();
      await _plugin.cancelAll();
      return;
    }
    await _ensurePlugin();
    await _ensurePermission();
    _schedule();
    await refresh();
  }

  Future<void> refresh() => _poll();

  void handleTap(String payload) {
    pendingPayload = payload;
    _openPending();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _watching && _enabled) {
      unawaited(() async {
        await _ensurePermission();
        await refresh();
      }());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (identical(instance, this)) instance = null;
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _seen.addAll(prefs.getStringList(_seenKey) ?? const <String>[]);
    _prefsLoaded = true;
    _notify();
  }

  Future<void> _ensurePlugin() async {
    if (_pluginReady || !mobileSupported) return;
    const android = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: onBldTrackNotificationTap,
    );
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'BldTrack alerts',
              description: 'Tasks, approvals, orders, and other updates',
              importance: Importance.max,
            ),
          );
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        (launch?.notificationResponse?.payload?.isNotEmpty ?? false)) {
      pendingPayload = launch!.notificationResponse!.payload;
    }
    _pluginReady = true;
  }

  Future<bool> _notificationsAllowed() async {
    if (!mobileSupported || !_pluginReady) return false;
    if (Platform.isAndroid) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled ?? false;
    }
    return _permissionGranted;
  }

  Future<bool> _ensurePermission() {
    final current = _permissionInFlight;
    if (current != null) return current;
    final future = _requestPermission();
    _permissionInFlight = future;
    return future.whenComplete(() {
      if (identical(_permissionInFlight, future)) _permissionInFlight = null;
    });
  }

  Future<bool> _requestPermission() async {
    if (!mobileSupported || !_pluginReady) return false;
    var granted = false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final enabled = await android?.areNotificationsEnabled();
        if (enabled == true) {
          granted = true;
        } else {
          final result = await android?.requestNotificationsPermission();
          granted = result ?? false;
        }
      } else if (Platform.isIOS) {
        final result = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        granted = result ?? false;
      }
    } on PlatformException catch (e) {
      if (e.code != 'permissionRequestInProgress') return _permissionGranted;
      granted = await _notificationsAllowed();
    }
    if (granted != _permissionGranted) {
      _permissionGranted = granted;
      _notify();
    }
    return granted;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_watching || !_enabled) return;
    _timer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (!_watching || !_enabled || _polling || _disposed) return;
    _polling = true;
    var dirty = false;
    try {
      final result = await _api.list({'page': 1, 'limit': 30});
      if (!_watching || _disposed) return;
      final unreadOnPage = result.items.where(notificationIsUnread).length;
      final nextCount = result.unreadCount > 0 ? result.unreadCount : unreadOnPage;
      if (nextCount != _unreadCount) {
        _unreadCount = nextCount;
        _notify();
      }

      final waitingForPermission = mobileSupported && !_permissionGranted;
      for (final row in result.items) {
        final id = idOf(row);
        if (id == null || id.isEmpty) continue;
        if (!notificationIsUnread(row)) {
          dirty = _remember(id) || dirty;
          continue;
        }
        if (_seen.contains(id) || waitingForPermission || !mobileSupported) continue;
        dirty = _remember(id) || dirty;
        await _showRow(row);
      }
      if (dirty) await _persistSeen();
    } catch (_) {
      // Keep the last badge if the notifications request fails.
    } finally {
      _polling = false;
    }
  }

  bool _remember(String id) {
    final added = _seen.add(id);
    if (_seen.length <= 400) return added;
    final drop = _seen.take(_seen.length - 300).toList();
    _seen.removeAll(drop);
    return true;
  }

  Future<void> _persistSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenKey, _seen.toList());
  }

  Future<void> _showRow(Map<String, dynamic> row) async {
    if (!_pluginReady) return;
    final id = idOf(row) ?? '';
    final title = (row['title']?.toString().trim().isNotEmpty ?? false)
        ? row['title'].toString().trim()
        : 'BldTrack';
    final body = (row['body'] ?? row['message'])?.toString().trim() ?? '';
    final metadata = row['metadata'];
    final meta = metadata is Map ? Map<String, dynamic>.from(metadata) : null;
    final payload = jsonEncode({
      'id': id,
      'link': row['link'] ?? meta?['link'],
      'type': row['type'],
      'entityType': row['entityType'] ?? meta?['entityType'],
      'entityId': idOf(row['entityId'] ?? meta?['entityId']),
      'project': idOf(row['project'] ?? meta?['projectId'] ?? meta?['project']),
      'metadata': {
        'link': meta?['link'],
        'section': meta?['section'],
        'entityType': meta?['entityType'],
        'entityId': idOf(meta?['entityId']),
        'projectId': idOf(meta?['projectId'] ?? meta?['project']),
      },
    });
    try {
      await _plugin.show(
        id: id.hashCode & 0x3fffffff,
        title: title,
        body: body.isEmpty ? null : body,
        notificationDetails: _details(),
        payload: payload,
      );
    } catch (_) {}
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'BldTrack alerts',
        channelDescription: 'Tasks, approvals, orders, and other updates',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@drawable/ic_stat_notify',
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  void _openPending() {
    final payload = pendingPayload;
    if (payload == null || !_watching || _router == null || _disposed) return;
    pendingPayload = null;
    Map<String, dynamic> row;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      row = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final id = idOf(row);
    final path = notificationRouteFor(row);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || _router == null) return;
      if (id != null && id.isNotEmpty) {
        try {
          await _api.markRead(id);
        } catch (_) {}
      }
      try {
        _router!.push(path);
      } catch (_) {
        _router!.go('/notifications');
      }
      unawaited(refresh());
    });
  }

  void _notify() {
    if (_disposed) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }
}
