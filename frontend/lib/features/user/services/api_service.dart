import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/project.dart';
import '../models/flowchart.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080';
  static const int _currentUserId = 1;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-User-ID': _currentUserId.toString(),
      };

  Future<List<Project>> listProjects() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/projects'),
      headers: _headers,
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
      Uri.parse('$baseUrl/api/projects'),
      headers: _headers,
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
      Uri.parse('$baseUrl/api/projects/$id'),
      headers: _headers,
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
      Uri.parse('$baseUrl/api/projects/$id'),
      headers: _headers,
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete: ${response.statusCode}');
    }
  }
  
  Future<Project> getProject(int id) async {
    final r = await http.get(
      Uri.parse('$baseUrl/api/projects/$id'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
    return Project.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }
}

