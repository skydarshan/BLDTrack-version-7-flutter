import 'package:flutter/foundation.dart';

/// API configuration.
///
/// **Production / TestFlight / Play (native):** always uses the live API.
/// Default: [liveApiBaseUrl].
///
/// **Flutter web (Chrome) local demo against live API:** browsers block CORS to
/// the live host from localhost. Use the proxy:
/// ```bash
/// node scripts/dev_api_proxy.js
/// flutter run -d chrome --web-hostname=127.0.0.1 \
///   --dart-define=API_BASE_URL=http://127.0.0.1:8787
/// ```
/// The proxy forwards to [liveApiBaseUrl].
///
/// Override any build with:
/// `--dart-define=API_BASE_URL=https://api.bldtrack.ai`
class ApiConfig {
  ApiConfig._();

  /// Canonical live backend (same as React production).
  static const String liveApiBaseUrl = 'https://api.bldtrack.ai';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: liveApiBaseUrl,
  );

  static String get apiV1Base => '$apiBaseUrl/api/v1';

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// True when talking to the real hosted API (not a local proxy / local node).
  static bool get isLiveApi {
    final u = apiBaseUrl.toLowerCase();
    return u.contains('bldtrack.ai') || u.contains('avidus');
  }

  /// Local CORS proxy in front of live (Chrome web only).
  static bool get isLiveApiProxy {
    final u = apiBaseUrl.toLowerCase();
    return u.contains('127.0.0.1:8787') || u.contains('localhost:8787');
  }

  /// Shown on auth screens in debug builds.
  static String get debugLabel {
    if (!kDebugMode) return '';
    if (isLiveApiProxy) return 'API: live (via proxy $apiBaseUrl)';
    if (apiBaseUrl == liveApiBaseUrl || isLiveApi) return 'API: live ($apiBaseUrl)';
    return 'API: $apiBaseUrl';
  }

  static bool get isLikelyWebCorsIssue =>
      kIsWeb &&
      apiBaseUrl.startsWith('https://') &&
      (apiBaseUrl.contains('bldtrack.ai') || apiBaseUrl.contains('avidus'));
}
