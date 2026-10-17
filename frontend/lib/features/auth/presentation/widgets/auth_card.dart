import 'package:flutter/material.dart';
import 'auth_colors.dart';
import 'auth_dimensions.dart';

// карточка с тенью, в которой лежит форма
class AuthCard extends StatelessWidget {
  final Widget child;

  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AuthDimensions.cardHorizontalPadding,
        vertical: AuthDimensions.cardVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: AuthColors.surface,
        borderRadius: BorderRadius.circular(AuthDimensions.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AuthColors.cardShadow,
            blurRadius: AuthDimensions.cardShadowBlur,
            offset: AuthDimensions.cardShadowOffset,
          ),
        ],
      ),
      child: child,
    );
  }
}
