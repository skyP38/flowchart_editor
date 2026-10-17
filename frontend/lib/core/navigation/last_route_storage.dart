import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Запоминает, на каком экране был пользователь
class LastRouteStorage extends ChangeNotifier {
  LastRouteStorage._();
  static final LastRouteStorage instance = LastRouteStorage._();

  static const _key = 'app.last_route';

  static const routeProjects = 'projects';
  static const routeSessions = 'sessions';

  String _tab = routeProjects;
  int? _projectId;
  int? _flowchartId;
  bool _isGuest = false;
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
        _isGuest = (m['isGuest'] as bool?) ?? false;
      } catch (_) {}
    }
    _initialized = true;
    notifyListeners();
  }

  String get tab => _tab;
  int? get projectId => _projectId;
  int? get flowchartId => _flowchartId;
  bool get isGuest => _isGuest;

  Future<void> setTab(String tab) async {
    if (_tab == tab) return;
    _tab = tab;
    await _persist();
    notifyListeners();
  }

  Future<void> setProject(int? id) async {
    if (_projectId == id) return;
    _projectId = id;
    if (id == null) _flowchartId = null;
    await _persist();
    notifyListeners();
  }

  Future<void> setFlowchart(int? id) async {
    if (_flowchartId == id) return;
    _flowchartId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> setGuest(bool value) async {
    if (_isGuest == value) return;
    _isGuest = value;
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _tab = routeProjects;
    _projectId = null;
    _flowchartId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'tab': _tab,
        'projectId': _projectId,
        'flowchartId': _flowchartId,
        'isGuest': _isGuest,
      }),
    );
  }
}
