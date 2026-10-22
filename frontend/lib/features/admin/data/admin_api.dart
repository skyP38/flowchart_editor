import '../../../core/network/api_client.dart';
import '../../../core/network/api_paths.dart';
import '../models/admin_user.dart';
import '../models/admin_session.dart';
import '../models/admin_log.dart';

class AdminApi {
  final ApiClient _client;

  const AdminApi(this._client);

  Future<List<AdminUser>> listUsers() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiPaths.adminUsers,
    );
    final users = response['users'] as List<dynamic>? ?? const <dynamic>[];
    return users
        .map((value) => AdminUser.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AdminUser> createUser({
    required String login,
    required String name,
    required String password,
    required String role,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.adminUsers,
      data: {'login': login, 'uname': name, 'password': password, 'role': role},
    );
    return AdminUser.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<List<AdminSession>> listSessions() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiPaths.adminSessions,
    );
    final sessions =
        response['sessions'] as List<dynamic>? ?? const <dynamic>[];
    return sessions
        .map((value) => AdminSession.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> revokeSession(int id) async {
    await _client.delete<void>(ApiPaths.adminSession(id));
  }

  Future<AdminLogPage> listLogs({int limit = 10, int offset = 0}) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiPaths.adminLogs,
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return AdminLogPage.fromJson(response);
  }

  Future<void> deleteUser(int id) async {
    await _client.delete<void>(ApiPaths.adminUser(id));
  }
}
