import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../core/org/org_modules.dart';
import '../../core/storage/token_storage.dart';
import '../auth/providers/auth_provider.dart';
import '../settings/services/settings_apis.dart';
import '../settings/utils/permissions.dart';

class OrgSession extends ChangeNotifier {
  OrgSession({
    required SettingsApis settingsApis,
    required TokenStorage tokenStorage,
    required AuthProvider auth,
  })  : _settingsApis = settingsApis,
        _tokenStorage = tokenStorage,
        _auth = auth {
    _auth.addListener(_onAuth);
  }

  final SettingsApis _settingsApis;
  final TokenStorage _tokenStorage;
  final AuthProvider _auth;

  Map<String, dynamic>? _organization;
  String _workspace = 'procurement';
  bool _loading = false;

  Map<String, dynamic>? get organization => _organization;
  String get workspace => _workspace;
  bool get loading => _loading;

  Permissions get _perms => Permissions(_auth.user);

  /// Org-level enabled products (ignores user role).
  List<String> get enabledWorkspaces => getEnabledWorkspaces(_organization);

  /// Products this user may access (org enabled ∩ role permissions).
  List<String> get accessibleWorkspaces =>
      _perms.accessibleWorkspaces(_organization);

  /// Org-enabled products this user may open (never bypass org module entitlements).
  bool canAccessWorkspace(String workspace) =>
      accessibleWorkspaces.contains(workspace);

  bool hasModule(String module, [String? sub]) =>
      orgHasModule(_organization, module, sub);

  /// User can see/use this org submodule in navigation.
  bool canUseSubmodule(String module, String sub) =>
      hasModule(module, sub) && canAccessWorkspace(module);

  Future<void> bootstrap() async {
    if (!_auth.isAuthenticated) {
      _organization = null;
      notifyListeners();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _organization = await _settingsApis.getOrganization();
      final stored = await _tokenStorage.getWorkspace();
      _workspace = resolveActiveWorkspaceForUser(
        _organization,
        stored,
        _perms.modulePermissions,
        isSuperAdmin: _perms.isSuperAdmin,
      );
      await _tokenStorage.saveWorkspace(_workspace);
    } on ApiException {
      _organization ??= null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setWorkspace(String next) async {
    if (!accessibleWorkspaces.contains(next)) return;
    _workspace = next;
    await _tokenStorage.saveWorkspace(next);
    notifyListeners();
  }

  void _onAuth() {
    if (_auth.isAuthenticated) {
      refresh();
    } else {
      _organization = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
