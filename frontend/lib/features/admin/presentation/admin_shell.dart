import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../user/screens/home_shell.dart';
import 'admin_sessions_screen.dart';
import 'admin_users_screen.dart';
import 'admin_logs_screen.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  // bool _showEditor = false;
  // bool _showSessions = false;
  // bool _showLogs = false;
  // bool _restored = false;

  // @override
  // void initState() {
  //   super.initState();
  //   _restore();
  // }

  @override
  Widget build(BuildContext context) {
    final screen = context.select<LastRouteStorage, String>(
      (s) => s.adminScreen,
    );
    final storage = context.read<LastRouteStorage>();

    void go(String target) => storage.setAdminScreen(target);

    switch (screen) {
      case LastRouteStorage.adminEditorScreen:
        return HomeShell(
          onReturnToAdmin: () => go(LastRouteStorage.adminUsersScreen),
        );

      case LastRouteStorage.adminSessionsScreen:
        return AdminSessionsScreen(
          onOpenEditor: () => go(LastRouteStorage.adminEditorScreen),
          onOpenUsers: () => go(LastRouteStorage.adminUsersScreen),
          onOpenLogs: () => go(LastRouteStorage.adminLogsScreen),
        );

      case LastRouteStorage.adminLogsScreen:
        return AdminLogsScreen(
          onOpenEditor: () => go(LastRouteStorage.adminEditorScreen),
          onOpenUsers: () => go(LastRouteStorage.adminUsersScreen),
          onOpenSessions: () => go(LastRouteStorage.adminSessionsScreen),
        );

      case LastRouteStorage.adminUsersScreen:
      default:
        return AdminUsersScreen(
          onOpenEditor: () => go(LastRouteStorage.adminEditorScreen),
          onOpenSessions: () => go(LastRouteStorage.adminSessionsScreen),
          onOpenLogs: () => go(LastRouteStorage.adminLogsScreen),
        );
    }
  }
  //   if (!_restored) {
  //     return const Scaffold(body: Center(child: CircularProgressIndicator()));
  //   }
  //   if (_showEditor) {
  //     return HomeShell(
  //       onReturnToAdmin: () => _openScreen(
  //         AdminRouteStorage.usersScreen,
  //       ), //=> setState(() => _showEditor = false),
  //     );
  //   }
  //   if (_showSessions) {
  //     return AdminSessionsScreen(
  //       onOpenEditor: () => _openScreen(AdminRouteStorage.editorScreen),
  //       onOpenUsers: () => _openScreen(AdminRouteStorage.usersScreen),
  //       onOpenLogs: () => _openScreen(AdminRouteStorage.logsScreen),
  //     );
  //   }
  //   if (_showLogs) {
  //     return AdminLogsScreen(
  //       onOpenEditor: () => _openScreen(AdminRouteStorage.editorScreen),
  //       onOpenUsers: () => _openScreen(AdminRouteStorage.usersScreen),
  //       onOpenSessions: () => _openScreen(AdminRouteStorage.sessionsScreen),
  //     );
  //   }
  //   return AdminUsersScreen(
  //     onOpenEditor: () => _openScreen(AdminRouteStorage.editorScreen),
  //     onOpenSessions: () => _openScreen(AdminRouteStorage.sessionsScreen),
  //     onOpenLogs: () => _openScreen(AdminRouteStorage.logsScreen),
  //   );
  // }
  //   return AdminSessionsScreen(
  //     onOpenEditor: () => setState(() {
  //       _showEditor = true;
  //       _showSessions = false;
  //       _showLogs = false;
  //     }),
  //     onOpenUsers: () => setState(() {
  //       _showSessions = false;
  //       _showLogs = false;
  //     }),
  //     onOpenLogs: () => setState(() {
  //       _showSessions = false;
  //       _showLogs = true;
  //     }),
  //   );
  // }

  // if (_showLogs) {
  //   return AdminLogsScreen(
  //     onOpenEditor: () => setState(() {
  //       _showEditor = true;
  //       _showSessions = false;
  //       _showLogs = false;
  //     }),
  //     onOpenUsers: () => setState(() {
  //       _showLogs = false;
  //       _showSessions = false;
  //     }),
  //     onOpenSessions: () => setState(() {
  //       _showLogs = false;
  //       _showSessions = true;
  //     }),
  //   );
  // }

  //   return AdminUsersScreen(
  //     onOpenEditor: () => setState(() {
  //       _showEditor = true;
  //       _showSessions = false;
  //       _showLogs = false;
  //     }),
  //     onOpenSessions: () => setState(() {
  //       _showSessions = true;
  //       _showLogs = false;
  //     }),
  //     onOpenLogs: () => setState(() {
  //       _showLogs = true;
  //       _showSessions = false;
  //     }),
  //   );
  // }
}
