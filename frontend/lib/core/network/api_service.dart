import '../../features/user/models/project.dart';
import '../../features/user/models/flowchart.dart';
// import '../../features/user/models/session.dart';
import 'api_client.dart';
import 'api_paths.dart';

// import 'json_keys.dart';

class ApiService {
  final ApiClient _client;

  ApiService(this._client);
  // static const String baseUrl = 'http://localhost:8080';

  Future<List<Project>> listProjects() async {
    final dynamic response = await _client.get<dynamic>(ApiPaths.projects);

    if (response == null) {
      return const <Project>[];
    }

    final List<dynamic> data;

    if (response is List) {
      data = response;
    } else if (response is Map && response['projects'] is List) {
      data = response['projects'] as List<dynamic>;
    } else {
      throw const FormatException(
        'Unexpected response format when loading projects',
      );
    }

    return data
        .map((item) {
          return Project.fromJson(Map<String, dynamic>.from(item as Map));
        })
        .toList(growable: false);
  }

  Future<Project> createProject(String name) async {
    final json = await _client.post<Map<String, dynamic>>(
      ApiPaths.projects,
      data: {'name': name},
    );
    return Project.fromJson(json);
  }

  Future<Project> renameProject(int id, String newName) async {
    final json = await _client.patch<Map<String, dynamic>>(
      ApiPaths.project(id),
      data: {'name': newName},
    );
    return Project.fromJson(json);
  }

  Future<void> deleteProject(int id) async {
    await _client.delete<void>(ApiPaths.project(id));
  }

  Future<Project> getProject(int id) async {
    final json = await _client.get<Map<String, dynamic>>(ApiPaths.project(id));
    return Project.fromJson(json);
  }

  Future<Flowchart> createFlowchart(int projectId, String name) async {
    final json = await _client.post<Map<String, dynamic>>(
      ApiPaths.flowcharts(projectId),
      data: {'name': name},
    );
    return Flowchart.fromJson(json);
  }

  Future<void> deleteFlowchart(int projectId, int flowchartId) async {
    await _client.delete<void>(ApiPaths.flowchart(projectId, flowchartId));
  }

  Future<Map<String, dynamic>> getFlowchartContent(
    int projectId,
    int flowchartId,
  ) async {
    return await _client.get<Map<String, dynamic>>(
      ApiPaths.flowchartContent(projectId, flowchartId),
    );
  }

  Future<void> updateFlowchartContent(
    int projectId,
    int flowchartId,
    Map<String, dynamic> content,
  ) async {
    await _client.put<void>(
      ApiPaths.flowchartContent(projectId, flowchartId),
      data: content,
    );
  }

  // Future<List<Session>> listSessions() async {
  //   final json = await _client.get<Map<String, dynamic>>(ApiPaths.sessions);
  //   final list =
  //       (json[JsonKeys.sessions] as List<dynamic>?) ?? const <dynamic>[];
  //   return list
  //       .map((e) => Session.fromJson(e as Map<String, dynamic>))
  //       .toList();
  // }

  // Future<void> closeSession(int sessionId) async {
  //   await _client.delete<void>(ApiPaths.session(sessionId));
  // }
}
