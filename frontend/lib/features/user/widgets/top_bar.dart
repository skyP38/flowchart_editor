import 'package:flutter/material.dart';

class TopBar extends StatelessWidget {
  final VoidCallback? onNewProject;
  const TopBar({super.key, this.onNewProject});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 73,
      padding: const EdgeInsets.symmetric(
        horizontal: 40,
        vertical: 18,
      ),
      color: Colors.white,
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 380,
            height: 37,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.search,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
                SizedBox(width: 8),
                Text(
                  'Search for projects and flowcharts...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),

          InkWell(
            onTap: onNewProject,
            borderRadius: BorderRadius.circular(8),
            child: Container (
              height: 37,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF6750A4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'New project',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
