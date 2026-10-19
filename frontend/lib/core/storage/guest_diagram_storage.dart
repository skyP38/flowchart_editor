import 'package:shared_preferences/shared_preferences.dart';

// Хранит гостевой черновик - последнюю схему с которой работал неавторизованный пользователь
class GuestDiagramStorage {
  GuestDiagramStorage._();
  static final GuestDiagramStorage instance = GuestDiagramStorage._();

  static const _key = 'app.guest_diagram';

  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> save(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
