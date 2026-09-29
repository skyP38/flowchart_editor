import '../../../../core/network/api_client.dart';
import '../models/auth_response.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';
import '../models/session.dart';

class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<AuthResponse> register({
    required String login,
    required String name,
    required String password,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      data: {'login': login, 'name': name, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> login({
    required String login,
    required String password,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login': login, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return AuthTokens.fromJson(json);
  }

  Future<void> logout(String refreshToken) async {
    await _client.post<void>(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }

  Future<User> me() async {
    final json = await _client.get<Map<String, dynamic>>('/auth/me');
    return User.fromJson(json);
  }

  Future<List<Session>> sessions() async {
    final json = await _client.get<List<dynamic>>('/auth/sessions');
    return json
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeSession(int sessionId) async {
    await _client.delete<void>('/auth/sessions/$sessionId');
  }
}
