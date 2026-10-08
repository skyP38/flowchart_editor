import 'package:flutter/material.dart';

class HeaderButton extends StatelessWidget {
  final String text;
  final Color background;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  const HeaderButton({
    required this.text,
    required this.background,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
