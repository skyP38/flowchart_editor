import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_dimensions.dart';
import 'auth_typ.dart';

class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AuthDimensions.bannerHorizontalPadding,
        vertical: AuthDimensions.bannerVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: AuthColors.errorBg,
        borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
        border: Border.all(color: AuthColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: AuthColors.errorText,
            size: AuthDimensions.iconSm,
          ),
          const SizedBox(width: AuthDimensions.gapSm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AuthColors.errorText,
                fontSize: AuthTypography.fontSizeXs,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
