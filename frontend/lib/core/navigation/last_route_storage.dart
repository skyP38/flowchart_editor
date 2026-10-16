import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Запоминает, на каком экране был пользователь
class LastRouteStorage {
  LastRouteStorage._();
  static final LastRouteStorage instance = LastRouteStorage._();

  static const _key = 'app.last_route';

  static const routeProjects = 'projects';
  static const routeSessions = 'sessions';

  String _tab = routeProjects;
  int? _projectId;
  int? _flowchartId;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _tab = (m['tab'] as String?) ?? routeProjects;
        _projectId = m['projectId'] as int?;
        _flowchartId = m['flowchartId'] as int?;
      } catch (_) {}
    }
    _initialized = true;
  }

  String get tab => _tab;
  int? get projectId => _projectId;
  int? get flowchartId => _flowchartId;

  Future<void> setTab(String tab) async {
    if (_tab == tab) return;
    _tab = tab;
    await _persist();
  }

  Future<void> setProject(int? id) async {
    if (_projectId == id) return;
    _projectId = id;
    if (id == null) _flowchartId = null;
    await _persist();
  }

  Future<void> setFlowchart(int? id) async {
    if (_flowchartId == id) return;
    _flowchartId = id;
    await _persist();
  }

  Future<void> clear() async {
    _tab = routeProjects;
    _projectId = null;
    _flowchartId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'tab': _tab,
        'projectId': _projectId,
        'flowchartId': _flowchartId,
      }),
    );
  }
}
