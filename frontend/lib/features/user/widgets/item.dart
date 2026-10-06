import 'package:flutter/material.dart';

class NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback? onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.title,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFF1EDFA)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active
                  ? const Color(0xFF6750A4)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
                color: active
                    ? const Color(0xFF6750A4)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
