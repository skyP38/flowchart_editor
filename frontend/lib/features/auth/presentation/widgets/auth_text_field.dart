import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_dimensions.dart';
import 'auth_typ.dart';

// Универсальное текстовое поле для форм авторизации
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: AuthTypography.fontSizeMd),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AuthColors.hint,
          fontSize: AuthTypography.fontSizeMd,
        ),
        errorText: errorText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AuthDimensions.fieldHorizontalPadding,
          vertical: AuthDimensions.fieldVerticalPadding,
        ),
        filled: true,
        fillColor: AuthColors.surface,
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
          borderSide: const BorderSide(
            color: AuthColors.border,
            width: AuthDimensions.borderWidthThin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
          borderSide: const BorderSide(
            color: AuthColors.primary,
            width: AuthDimensions.borderWidthMedium,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
          borderSide: const BorderSide(
            color: Colors.red,
            width: AuthDimensions.borderWidthThin,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
          borderSide: const BorderSide(
            color: Colors.red,
            width: AuthDimensions.borderWidthMedium,
          ),
        ),
      ),
    );
  }
}
