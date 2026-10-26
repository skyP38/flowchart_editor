import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class BrowserLocationService {
  static Future<Position?> getCurrentPosition() async {
    // В этом варианте геолокация собирается только в браузере.
    if (!kIsWeb) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('Не удалось получить геолокацию: $e');
      return null;
    }
  }

  static String? formatLocation(Position? position) {
    if (position == null) return null;

    // Округляем координаты, чтобы не хранить лишнюю точность.
    return '${position.latitude.toStringAsFixed(3)}, '
        '${position.longitude.toStringAsFixed(3)}';
  }
}
