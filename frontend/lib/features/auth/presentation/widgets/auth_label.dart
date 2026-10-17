import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_dimensions.dart';
import 'auth_typ.dart';

// Подпись над полем ввода
class AuthLabel extends StatelessWidget {
  final String text;

  const AuthLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AuthDimensions.gapSm),
      child: Text(
        text,
        style: const TextStyle(
          color: AuthColors.text,
          fontSize: AuthTypography.fontSizeSm,
          fontWeight: AuthTypography.weightMedium,
        ),
      ),
    );
  }
}
