import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../user/screens/home_shell.dart';
import 'admin_sessions_screen.dart';
import 'admin_users_screen.dart';
import 'admin_logs_screen.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

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
}
