import '../../../../core/network/api_client.dart';
import '../models/auth_response.dart';
import '../models/user.dart';
import '../../../user/models/session.dart';
import '../../../../core/network/api_paths.dart';
import '../../../../core/network/json_keys.dart';
import '../models/auth_tokens.dart';

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
      ApiPaths.register,
      data: {'login': login, 'uname': uname, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> login({
    required String login,
    required String password,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      ApiPaths.login,
      data: {'login': login, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _client.post<Map<String, dynamic>>(
      ApiPaths.refresh,
      data: {JsonKeys.refreshToken: refreshToken},
    );
    return AuthTokens.fromJson(json);
  }

  Future<void> logout(String refreshToken) async {
    await _client.post<void>(
      ApiPaths.logout,
      data: {JsonKeys.refreshToken: refreshToken},
    );
  }

  Future<User> me() async {
    final json = await _client.get<Map<String, dynamic>>(ApiPaths.me);
    return User.fromJson(json);
  }

  Future<List<Session>> sessions() async {
    final json = await _client.get<Map<String, dynamic>>(ApiPaths.sessions);
    final list =
        (json[JsonKeys.sessions] as List<dynamic>? ?? const <dynamic>[]);
    return list
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeSession(int sessionId) async {
    await _client.delete<void>(ApiPaths.session(sessionId));
  }

  Future<void> revokeAllSessions() async {
    await _client.delete<void>(ApiPaths.sessions);
  }
}
