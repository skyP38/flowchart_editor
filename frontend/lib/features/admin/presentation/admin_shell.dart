import 'package:flutter/material.dart';

import '../../user/screens/home_shell.dart';
import 'admin_sessions_screen.dart';
import 'admin_users_screen.dart';
import 'admin_logs_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _showEditor = false;
  bool _showSessions = false;
  bool _showLogs = false;

  @override
  Widget build(BuildContext context) {
    if (_showEditor) {
      return HomeShell(onReturnToAdmin: () => setState(() => _showEditor = false));
    }
    if (_showSessions) {
      return AdminSessionsScreen(
        onOpenEditor: () => setState(() {
          _showEditor = true;
          _showSessions = false;
          _showLogs = false;
        }),
        onOpenUsers: () => setState(() {
          _showSessions = false;
          _showLogs = false;
        }),
        onOpenLogs: () => setState(() {
          _showSessions = false;
          _showLogs = true;
        }),
      );
    }

    if (_showLogs) {
      return AdminLogsScreen(
        onOpenEditor: () => setState(() {
          _showEditor = true;
          _showSessions = false;
          _showLogs = false;
        }),
        onOpenUsers: () => setState(() {
          _showLogs = false;
          _showSessions = false;
        }),
        onOpenSessions: () => setState(() {
          _showLogs = false;
          _showSessions = true;
        }),
      );
    }

    return AdminUsersScreen(
      onOpenEditor: () => setState(() {
        _showEditor = true;
        _showSessions = false;
        _showLogs = false;
      }),
      onOpenSessions: () => setState(() {
        _showSessions = true;
        _showLogs = false;
      }),
      onOpenLogs: () => setState(() {
        _showLogs = true;
        _showSessions = false;
      }),
    );
  }
}
