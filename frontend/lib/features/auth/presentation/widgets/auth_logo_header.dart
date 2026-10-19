import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_dimensions.dart';
import 'auth_typ.dart';

class AuthLogoHeader extends StatelessWidget {
  const AuthLogoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AuthDimensions.logoIconPadding),
          decoration: BoxDecoration(
            color: AuthColors.primary,
            borderRadius: BorderRadius.circular(AuthDimensions.radiusSm),
          ),
          child: const Icon(
            Icons.close_rounded, // TODO: заменить на логотип
            size: AuthDimensions.iconMd,
          ),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Text(
            'Flowchart Editor',
            style: TextStyle(
              fontSize: AuthTypography.fontSizeXl,
              fontWeight: AuthTypography.weightBold,
              color: AuthColors.textStrong,
            ),
          ),
        ),
      ],
    );
  }
}
