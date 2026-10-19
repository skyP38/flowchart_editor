import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_dimensions.dart';
import 'auth_typ.dart';

// Основная кнопка форм авторизации с режимом загрузки
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AuthColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AuthColors.primary.withValues(alpha: 0.6),
        disabledForegroundColor: AuthColors.surfaceMuted,
        padding: const EdgeInsets.symmetric(
          vertical: AuthDimensions.buttonVerticalPadding,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? const SizedBox(
              width: AuthDimensions.progressSize,
              height: AuthDimensions.progressSize,
              child: CircularProgressIndicator(
                strokeWidth: AuthDimensions.progressStrokeWidth,
                valueColor: AlwaysStoppedAnimation(AuthColors.surface),
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: AuthTypography.fontSizeLg,
                fontWeight: AuthTypography.weightSemiBold,
              ),
            ),
    );
  }
}
