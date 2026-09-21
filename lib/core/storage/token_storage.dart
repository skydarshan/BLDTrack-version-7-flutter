import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/models/user_model.dart';

/// Persists access token and lightweight user profile securely.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'accessToken';
  static const _refreshKey = 'refreshToken';
  static const _userKey = 'user';
  static const _workspaceKey = 'activeWorkspace';

  final FlutterSecureStorage _storage;

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    required UserModel user,
  }) async {
    await _storage.write(key: _tokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<String?> getAccessToken() => _storage.read(key: _tokenKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<UserModel?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUser(UserModel user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _workspaceKey);
  }

  Future<void> saveWorkspace(String workspace) =>
      _storage.write(key: _workspaceKey, value: workspace);

  Future<String?> getWorkspace() => _storage.read(key: _workspaceKey);
}
