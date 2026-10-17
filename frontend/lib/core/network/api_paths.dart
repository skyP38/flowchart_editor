// Все пути API
abstract final class ApiPaths {
  // Auth
  static const login = '/api/auth/login';
  static const register = '/api/auth/register';
  static const refresh = '/api/auth/refresh';
  static const logout = '/api/auth/logout';
  static const me = '/api/auth/me';

  // Sessions
  static const sessions = '/api/sessions';
  static String session(int id) => '/api/sessions/$id';

  // Projects
  static const projects = '/api/projects';
  static String project(int id) => '/api/projects/$id';

  // Flowcharts
  static String flowcharts(int projectId) =>
      '/api/projects/$projectId/flowcharts';
  static String flowchart(int projectId, int flowchartId) =>
      '/api/projects/$projectId/flowcharts/$flowchartId';
  static String flowchartContent(int projectId, int flowchartId) =>
      '/api/projects/$projectId/flowcharts/$flowchartId/content';

  // Пути, к которым access-токен не добавляется и 401 не повторяется
  // Используется AuthInterceptor и RefreshInterceptor.
  static const _publicAuth = <String>[login, register, refresh];

  static bool isPublic(String path) =>
      _publicAuth.any((p) => path == p || path.startsWith('$p/'));
}
