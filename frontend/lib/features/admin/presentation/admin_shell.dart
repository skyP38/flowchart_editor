import 'package:flutter/material.dart';

import '../../user/screens/home_shell.dart';
import 'admin_sessions_screen.dart';
import 'admin_users_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _showEditor = false;
  bool _showSessions = false;

  @override
  Widget build(BuildContext context) {
    if (_showEditor) {
      return HomeShell(onReturnToAdmin: () => setState(() => _showEditor = false));
    }
    if (_showSessions) {
      return AdminSessionsScreen(
        onOpenUsers: () => setState(() => _showSessions = false),
        onOpenEditor: () => setState(() => _showEditor = true),
      );
    }
    return AdminUsersScreen(
      onOpenEditor: () => setState(() => _showEditor = true),
      onOpenSessions: () => setState(() => _showSessions = true),
    );
  }
}
