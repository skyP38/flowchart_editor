import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flowchart_editor_frontend/core/navigation/last_route_storage.dart';
import 'package:flowchart_editor_frontend/features/user/screens/home_shell.dart';

class AdminEditorRouter extends StatelessWidget {
  const AdminEditorRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.read<LastRouteStorage>();
    return HomeShell(
      onReturnToAdmin: () =>
          storage.setAdminScreen(LastRouteStorage.adminUsersScreen),
    );
  }
}
