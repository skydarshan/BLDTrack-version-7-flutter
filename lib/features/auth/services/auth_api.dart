import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );

    final root = res.data ?? const <String, dynamic>{};
    final data = _unwrapData(root);

    final accessToken = data['accessToken']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw ApiException(message: 'Login succeeded but no access token was returned.');
    }

    final userMap = data['user'];
    if (userMap is! Map<String, dynamic>) {
      throw ApiException(message: 'Login succeeded but user profile was missing.');
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: data['refreshToken']?.toString(),
      user: UserModel.fromJson(userMap),
    );
  }

  Future<AuthSession> registerOrganization(RegisterOrganizationRequest request) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/auth/register-organization',
      data: request.toJson(),
    );

    final root = res.data ?? const <String, dynamic>{};
    final data = _unwrapData(root);

    final auth = data['auth'];
    if (auth is! Map<String, dynamic>) {
      throw ApiException(message: 'Registration succeeded but auth payload was missing.');
    }

    final accessToken = auth['accessToken']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw ApiException(message: 'Registration succeeded but no access token was returned.');
    }

    final profile = data['user'] ?? data['admin'];
    if (profile is! Map<String, dynamic>) {
      throw ApiException(message: 'Registration succeeded but user profile was missing.');
    }

    final organization = data['organization'];
    final user = UserModel.fromJson({
      ...profile,
      if (organization is Map && organization['id'] != null)
        'organisation': organization['id'],
      'roleName': profile['role'] is Map
          ? (profile['role']['name']?.toString() ?? 'Super Admin')
          : 'Super Admin',
    });

    return AuthSession(
      accessToken: accessToken,
      refreshToken: auth['refreshToken']?.toString(),
      user: user,
    );
  }

  Future<UserModel> fetchMe() async {
    final res = await _client.get<Map<String, dynamic>>('/auth/me');
    final root = res.data ?? const <String, dynamic>{};
    final data = _unwrapData(root);
    final userMap = data['user'];
    if (userMap is! Map<String, dynamic>) {
      throw ApiException(message: 'Unable to load user profile.');
    }
    return UserModel.fromJson(userMap);
  }

  Future<void> logout() async {
    try {
      await _client.post<Map<String, dynamic>>('/auth/logout', data: {});
    } catch (_) {
      // Local session is cleared regardless of network result.
    }
  }

  /// Check org name / admin email availability during registration (step 1–2).
  Future<Map<String, dynamic>> checkRegistration({
    String? organizationName,
    String? adminEmail,
  }) async {
    final params = <String, dynamic>{};
    if (organizationName != null && organizationName.trim().isNotEmpty) {
      params['organizationName'] = organizationName.trim();
    }
    if (adminEmail != null && adminEmail.trim().isNotEmpty) {
      params['adminEmail'] = adminEmail.trim().toLowerCase();
    }
    final res = await _client.get<Map<String, dynamic>>(
      '/auth/check-registration',
      queryParameters: params.isEmpty ? null : params,
    );
    return _unwrapData(res.data ?? const {});
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> root) {
    final data = root['data'];
    if (data is Map<String, dynamic>) return data;
    return root;
  }
}
