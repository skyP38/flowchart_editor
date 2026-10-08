import '../../../../core/network/api_client.dart';
import '../models/auth_response.dart';
import '../models/user.dart';
import '../models/session.dart';

// слой над ApiClient: знает URL и DTO домена auth
class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<AuthResponse> register({
    required String login,
    required String uname,
    required String password,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {'login': login, 'uname': uname, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> login({
    required String login,
    required String password,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'login': login, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> refresh(String refreshToken) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return AuthResponse.fromJson(json);
  }

  Future<void> logout(String refreshToken) async {
    await _client.post<void>(
      '/api/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  }

  Future<User> me() async {
    final json = await _client.get<Map<String, dynamic>>('/api/auth/me');
    return User.fromJson(json);
  }

  Future<List<Session>> sessions() async {
    final json = await _client.get<Map<String, dynamic>>('/api/sessions');
    final list = (json['sessions'] as List<dynamic>? ?? const <dynamic>[]);
    return list
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeSession(int sessionId) async {
    await _client.delete<void>('/api/sessions/$sessionId');
  }

  Future<void> revokeAllSessions() async {
    await _client.delete<void>('/api/sessions');
  }
}
