import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/app/app_services.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/services/auth_api.dart';
import 'features/org/org_session.dart';
import 'features/pms/services/pms_services.dart';
import 'features/settings/services/settings_apis.dart';
import 'router/app_router.dart';
import 'router/app_router_refresh.dart';

class AvidusApp extends StatefulWidget {
  const AvidusApp({super.key});

  @override
  State<AvidusApp> createState() => _AvidusAppState();
}

class _AvidusAppState extends State<AvidusApp> {
  late final AuthProvider _authProvider;
  late final OrgSession _orgSession;
  late final AppServices _appServices;
  late final PmsServices _pmsServices;
  late final SettingsApis _settingsApis;
  late final AppRouterRefresh _routerRefresh;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    final tokenStorage = TokenStorage();
    late final AuthProvider authProvider;

    final apiClient = ApiClient(
      tokenStorage: tokenStorage,
      onUnauthorized: () => authProvider.handleUnauthorized(),
    );
    final authApi = AuthApi(apiClient);

    authProvider = AuthProvider(
      authApi: authApi,
      tokenStorage: tokenStorage,
    );

    _authProvider = authProvider;
    _settingsApis = SettingsApis(apiClient);
    _pmsServices = PmsServices(apiClient);
    _appServices = AppServices(apiClient);
    _orgSession = OrgSession(
      settingsApis: _settingsApis,
      tokenStorage: tokenStorage,
      auth: _authProvider,
    );
    _routerRefresh = AppRouterRefresh(_authProvider, _orgSession);
    _router = createAppRouter(_authProvider, _orgSession, _routerRefresh);
    _authProvider.bootstrap().then((_) => _orgSession.bootstrap());
  }

  @override
  void dispose() {
    _routerRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<OrgSession>.value(value: _orgSession),
        Provider<AppServices>.value(value: _appServices),
        Provider<PmsServices>.value(value: _pmsServices),
        Provider<SettingsApis>.value(value: _settingsApis),
      ],
      child: MaterialApp.router(
        title: 'BldTrack',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
