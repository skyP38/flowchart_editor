import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Хранит, на каком экране админ-панели находится администратор
class AdminRouteStorage extends ChangeNotifier {
  AdminRouteStorage._();
  static final AdminRouteStorage instance = AdminRouteStorage._();

  static const usersScreen = 'users';
  static const editorScreen = 'editor';
  static const sessionsScreen = 'sessions';
  static const logsScreen = 'logs';

  static const _prefsKey = 'admin.screen';

  String _screen = usersScreen;
  String get screen => _screen;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _screen = prefs.getString(_prefsKey) ?? usersScreen;
    } catch (_) {
      _screen = usersScreen;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setScreen(String screen) async {
    if (_screen == screen) return;
    _screen = screen;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, screen);
    } catch (_) {}
  }

  Future<void> clear() async {
    _screen = usersScreen;
    _initialized = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
