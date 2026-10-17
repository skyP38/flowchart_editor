import 'package:flutter/material.dart';

/// Общая палитра экранов авторизации
abstract final class AuthColors {
  static const primary = Color(0xFF6750A5);
  static const border = Color(0xFF9CA3AF);
  static const text = Color(0xFF374151);
  static const hint = Color(0xFF9CA3AF);

  // Surface / foreground
  static const surface = Color(0xFFFFFFFF); // Colors.white
  static const surfaceMuted = Color(0xB3FFFFFF); // Colors.white70
  static const textStrong = Color(0xDD000000); // Colors.black87

  static const errorBg = Color(0xFFFDECEC);
  static const errorBorder = Color(0xFFF5C2C7);
  static const errorText = Color(0xFFB02A37);
  static const errorField = Color(0xFFF44336); // Colors.red (границы поля)

  // Shadows
  static const cardShadow = Color(0x0D000000); // black @ 0.05
}
