import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'item.dart';
// import '../../../core/navigation/navigation_service.dart';
import '../../../core/navigation/last_route_storage.dart';

// import '../screens/screens.dart';
// import '../screens/sessions.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/domain/auth_state.dart';

class Sidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onReturnToAdmin;

  const Sidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.onReturnToAdmin,
  });

  // final String currentRoute;
  // const Sidebar({super.key, this.currentRoute = 'projects'});

  @override
  Widget build(BuildContext context) {
    // final nav = context.read<NavigationService>();
    final authState = context.watch<AuthRepository>().state;
    final user = authState is AuthAuthenticated
        ? authState.user
        : authState is AuthLoading
        ? authState.user
        : null;

    final name = user?.name?.trim();
    final login = user?.login?.trim();

    final displayName = name != null && name.isNotEmpty
        ? name
        : (login != null && login.isNotEmpty ? login : 'Пользователь');

    final displayLogin = login != null && login.isNotEmpty ? login : ' ';
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
                      Icons.schema,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'FlowChart Editor',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              NavItem(
                icon: Icons.folder_outlined,
                title: 'My projects',
                active: currentIndex == 0,
                onTap: () => onSelect(0),
                // active: currentRoute == 'projects',
                // onTap: currentRoute == 'projects'
                //     ? null
                //     : () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),

              NavItem(
                icon: Icons.shield_outlined,
                title: 'Sessions',
                active: currentIndex == 1,
                onTap: () => onSelect(1),
                // active: currentRoute == 'sessions',
                // onTap: currentRoute == 'sessions'
                //     ? null
                //     : () {
                //         Navigator.of(context).push(
                //           MaterialPageRoute(
                //             settings: const RouteSettings(
                //               name: LastRouteStorage.routeSessions,
                //             ),
                //             builder: (_) => const SessionScreen(),
                //           ),
                //         );
                //       },
              ),
              if (onReturnToAdmin != null)
                NavItem(
                  icon: Icons.arrow_back,
                  title: 'Admin panel',
                  active: false,
                  onTap: onReturnToAdmin,
                ),
              NavItem(
                icon: Icons.logout,
                title: 'Log out',
                active: false,
                onTap: () async {
                  final auth = context.read<AuthRepository>();
                  await auth.logout();
                  if (!context.mounted) return;
                  await LastRouteStorage.instance.clear();
                  // await context.read<NavigationService>().clear();
                  // if (!context.mounted) return;
                  // Navigator.of(context).popUntil((r) => r.isFirst);
                },
                // onTap: () async {
                //   debugPrint('Logout tapped');
                //   try {
                //     final authRepo = context.read<AuthRepository>();
                //     await authRepo.logout();
                //     debugPrint(
                //       'Logout done, stack=${Navigator.of(context).canPop()}',
                //     );
                //     if (context.mounted) {
                //       Navigator.of(context).popUntil((r) => r.isFirst);
                //     }
                //   } catch (e, st) {
                //     debugPrint('Logout error: $e\n$st');
                //   }
                // },
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 24),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFD9D9D9), width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayLogin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
