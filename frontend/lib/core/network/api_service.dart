import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../features/user/models/project.dart';
import '../../features/user/models/flowchart.dart';
import '../../features/auth/data/storage/secure_token_storage.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080';

  final _storage = SecureTokenStorage();  
  //final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getAccessToken();
    //const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciIsImlzcyI6ImJhY2tlbmQiLCJzdWIiOiIyIiwiZXhwIjoxNzkxNDEwNDEzLCJpYXQiOjE3OTE0MDk1MTMsImp0aSI6IjMifQ._z2kG02u3voE4VTxRcOGOLQX7d1frxgtWoDu41Jhxzg';
    return {
      'Content-Type': 'application/json',
      //if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Project>> listProjects() async {
    final response = await http.get(
      Uri.parse('http://localhost:8080/api/projects'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Loading error: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((json) => Project.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Project> createProject(String name) async {
    final response = await http.post(
      Uri.parse('http://localhost:8080/api/projects'),
      headers: await _headers(),
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create: ${response.statusCode}');
    }

    return Project.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Project> renameProject(int id, String newName) async {
    final response = await http.patch(
      Uri.parse('http://localhost:8080/api/projects/$id'),
      headers: await _headers(),
      body: jsonEncode({'name': newName}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to rename: ${response.statusCode}');
    }
    return Project.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteProject(int id) async {
    final response = await http.delete(
      Uri.parse('http://localhost:8080/api/projects/$id'),
      headers: await _headers(),
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete: ${response.statusCode}');
    }
  }
  
  Future<Project> getProject(int id) async {
    final r = await http.get(
      Uri.parse('http://localhost:8080/api/projects/$id'),
      headers: await _headers(),
    );
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
    return Project.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

Future<Flowchart> createFlowchart(int projectId, String name) async {
    final r = await http.post(
      Uri.parse('http://localhost:8080/api/projects/$projectId/flowcharts'),
      headers: await _headers(),
      body: jsonEncode({'name': name}),
    );
    if (r.statusCode != 201) {
      throw Exception('HTTP ${r.statusCode}');
    }
    return Flowchart.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<void> deleteFlowchart(int flowchartId) async {
    final r = await http.delete(
      Uri.parse('http://localhost:8080/api/flowcharts/$flowchartId'),
      headers: await _headers(),
    );
    if (r.statusCode != 204) {
      throw Exception('HTTP ${r.statusCode}');
    }
  }
}

