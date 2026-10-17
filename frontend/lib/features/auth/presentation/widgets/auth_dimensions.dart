import 'dart:ui';

// Размеры, отступы, радиусы, толщина обводок и тени для UI авторизации
abstract final class AuthDimensions {
  // Layout
  static const double contentMaxWidth = 420;
  static const double screenPadding = 24;
  static const double cardHorizontalPadding = 32;
  static const double cardVerticalPadding = 40;
  static const double buttonVerticalPadding = 16;
  static const double fieldHorizontalPadding = 16;
  static const double fieldVerticalPadding = 16;
  static const double bannerHorizontalPadding = 12;
  static const double bannerVerticalPadding = 10;
  static const double logoIconPadding = 6;

  // Gaps
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 20;
  static const double gapXxl = 24;
  static const double gapHuge = 32;

  // Radii
  static const double radiusSm = 8;
  static const double radiusLg = 16;

  // Icons
  static const double iconSm = 18;
  static const double iconMd = 20;
  static const double iconXl = 56;

  // Progress indicator
  static const double progressSize = 20;
  static const double progressStrokeWidth = 2;

  // Border widths
  static const double borderWidthThin = 1;
  static const double borderWidthMedium = 1.5;

  // Card shadow
  static const double cardShadowBlur = 20;
  static const double cardShadowAlpha = 0.05;
  static const Offset cardShadowOffset = Offset(0, 10);
}
