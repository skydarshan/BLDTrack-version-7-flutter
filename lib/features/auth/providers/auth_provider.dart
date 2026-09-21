import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';
import '../services/auth_api.dart';

enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthApi authApi,
    required TokenStorage tokenStorage,
  })  : _authApi = authApi,
        _tokenStorage = tokenStorage;

  final AuthApi _authApi;
  final TokenStorage _tokenStorage;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isBusy => _busy;
  String? get error => _error;

  Future<void> bootstrap() async {
    final token = await _tokenStorage.getAccessToken();
    final cachedUser = await _tokenStorage.getUser();

    if (token == null || token.isEmpty) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      notifyListeners();
      return;
    }

    _user = cachedUser;
    _status = AuthStatus.authenticated;
    notifyListeners();

    try {
      final me = await _authApi.fetchMe();
      _user = me;
      await _tokenStorage.updateUser(me);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearLocalSession();
      }
    } catch (_) {
      // Keep cached session if /me fails transiently.
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    return _runAuthAction(() async {
      final session = await _authApi.login(email: email, password: password);
      await _persistSession(session);
    });
  }

  Future<bool> register(RegisterOrganizationRequest request) async {
    return _runAuthAction(() async {
      final session = await _authApi.registerOrganization(request);
      await _persistSession(session);
    });
  }

  /// Reloads `/auth/me` so role permissions stay in sync after org module changes.
  Future<void> refreshMe() async {
    if (!isAuthenticated) return;
    try {
      final me = await _authApi.fetchMe();
      _user = me;
      await _tokenStorage.updateUser(me);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearLocalSession();
      }
    } catch (_) {
      // Keep cached user if /me fails transiently.
    }
  }

  Future<void> logout() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _authApi.logout();
    } finally {
      await _clearLocalSession();
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Called by ApiClient when a 401 is received on any request.
  void handleUnauthorized() {
    if (_status == AuthStatus.unauthenticated) return;
    _status = AuthStatus.unauthenticated;
    _user = null;
    notifyListeners();
  }

  Future<bool> _runAuthAction(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _persistSession(AuthSession session) async {
    await _tokenStorage.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      user: session.user,
    );
    _user = session.user;
    _status = AuthStatus.authenticated;
  }

  Future<void> _clearLocalSession() async {
    await _tokenStorage.clear();
    _user = null;
    _status = AuthStatus.unauthenticated;
  }
}
