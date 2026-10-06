import 'package:flutter/material.dart';
import 'item.dart';
import '../screens/screens.dart';

class Sidebar extends StatelessWidget {
  final String currentRoute;

  const Sidebar({
    super.key,
    this.currentRoute = 'projects',
  });

  void _go(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6750A4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'FlowChart Editor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              NavItem(
                icon: Icons.folder_outlined,
                title: 'My projects',
                active: currentRoute == 'projects',
                onTap: () => _go(context, const ProjectsScreen()),
              ),

              NavItem(
                icon: Icons.shield_outlined,
                title: 'Sessions',
                active: currentRoute == 'session',
              ),

              NavItem(
                icon: Icons.logout,
                title: 'Log out',
                active: currentRoute == 'logout',
              ),
            ],
          ),       
        ],
      ),
    );
  }
}
