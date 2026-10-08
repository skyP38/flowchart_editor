import '../../features/user/models/project.dart';
import '../../features/user/models/flowchart.dart';
import 'api_client.dart';

class ApiService {
  final ApiClient _client;

  ApiService(this._client);
  static const String baseUrl = 'http://localhost:8080';

  Future<List<Project>> listProjects() async {
    final List<dynamic> data = await _client.get<List<dynamic>>(
      '/api/projects',
    );
    return data
        .map((json) => Project.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Project> createProject(String name) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/projects',
      data: {'name': name},
    );
    return Project.fromJson(json);
  }

  Future<Project> renameProject(int id, String newName) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/api/projects/$id',
      data: {'name': newName},
    );
    return Project.fromJson(json);
  }

  Future<void> deleteProject(int id) async {
    await _client.delete<void>('/api/projects/$id');
  }

  Future<Project> getProject(int id) async {
    final json = await _client.get<Map<String, dynamic>>('/api/projects/$id');
    return Project.fromJson(json);
  }

  Future<Flowchart> createFlowchart(int projectId, String name) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/projects/$projectId/flowcharts',
      data: {'name': name},
    );
    return Flowchart.fromJson(json);
  }

  Future<void> deleteFlowchart(int flowchartId) async {
    await _client.delete<void>('/api/flowcharts/$flowchartId');
  }
}
