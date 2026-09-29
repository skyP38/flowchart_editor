import 'package:flutter/material.dart';

import 'auth_colors.dart';

class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AuthColors.errorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AuthColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: AuthColors.errorText,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AuthColors.errorText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
