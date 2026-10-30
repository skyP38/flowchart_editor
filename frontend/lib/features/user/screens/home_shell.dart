import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../../auth/domain/auth_repository.dart';
// import '../widgets/sidebar.dart';
import 'screens.dart';
import 'sessions.dart';
import 'project_screen.dart';
import '../widgets/user.dart';

class HomeShell extends StatefulWidget {
  final VoidCallback? onReturnToAdmin;

  const HomeShell({super.key, this.onReturnToAdmin});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _projects = 0;
  static const _sessions = 1;

  int _tab = _projects;
  bool _drillDownActive = false;

  @override
  void initState() {
    super.initState();
    if (LastRouteStorage.instance.isGuest) {
      LastRouteStorage.instance.setGuest(false);
    }

    final storage = LastRouteStorage.instance;
    _tab = storage.tab == LastRouteStorage.routeSessions
        ? _sessions
        : _projects;

    final pid = storage.projectId;
    if (pid != null) {
      _drillDownActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushProject(pid);
      });
    }
  }

  Future<void> _pushProject(int projectId) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => ProjectScreen(
          projectId: projectId,
          restoreFlowchartId: LastRouteStorage.instance.flowchartId,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _drillDownActive = false);
  }

  Future<void> _selectTab(int index) async {
    if (_tab == index) return;
    setState(() => _tab = index);
    await LastRouteStorage.instance.setTab(
      index == _sessions
          ? LastRouteStorage.routeSessions
          : LastRouteStorage.routeProjects,
    );
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();
    await LastRouteStorage.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 800;
    final isAdminMode = widget.onReturnToAdmin != null;
    final inSessions = _tab == _sessions;

    return Scaffold(
      appBar: AppBar(
        // Back-стрелка только если есть куда возвращаться.
        leading: inSessions
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to projects',
                onPressed: () => _selectTab(_projects),
              )
            : isAdminMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to admin panel',
                onPressed: widget.onReturnToAdmin,
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(inSessions ? 'Sessions' : 'Projects'),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E1E1E),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFD9D9D9), width: 1),
        ),

        //   actions: isAdminMode
        //       ? null
        //       : [
        //           IconButton(
        //             icon: const Icon(Icons.logout, color: Color(0xFF1E1E1E)),
        //             tooltip: 'Log out',
        //             onPressed: _logout,
        //           ),
        //           const SizedBox(width: 8),
        //         ],
        // ),
        actions: isMobile
            ? [
                // Мобилка: только logout-иконка (навигация — в bottom nav).
                if (!isAdminMode)
                  IconButton(
                    icon: const Icon(Icons.logout, color: Color(0xFF1E1E1E)),
                    tooltip: 'Log out',
                    onPressed: _logout,
                  ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: UserChip(compact: true),
                ),
              ]
            : [
                // Десктоп: горизонтальная полоса кнопок.
                TextButton.icon(
                  onPressed: () => _selectTab(_projects),
                  icon: const Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: Color(0xFF1E1E1E),
                  ),
                  label: Text(
                    'Projects',
                    style: TextStyle(
                      color: const Color(0xFF1E1E1E),
                      fontWeight: !inSessions
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: !inSessions
                        ? const Color(0xFFF3F4F6)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _selectTab(_sessions),
                  icon: const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: Color(0xFF1E1E1E),
                  ),
                  label: Text(
                    'Sessions',
                    style: TextStyle(
                      color: const Color(0xFF1E1E1E),
                      fontWeight: inSessions
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: inSessions
                        ? const Color(0xFFF3F4F6)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (!isAdminMode) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _logout,
                    label: const Text(
                      'Log out',
                      style: TextStyle(color: Color(0xFF1E1E1E)),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE3E3E3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(
                          color: Color(0xFF767676),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                const UserChip(),
                const SizedBox(width: 12),
              ],
      ),

      // body: Column(
      //   children: [
      //     if (!isMobile && !inSessions)
      //       Sidebar(currentIndex: _tab, onSelect: _selectTab),
      //     Expanded(
      //       child: _drillDownActive
      //           ? const SizedBox.shrink()
      //           : IndexedStack(
      //               index: _tab,
      //               children: const [ProjectsContent(), SessionScreen()],
      //             ),
      //     ),
      //   ],
      // ),
      body: _drillDownActive
          ? const SizedBox.shrink()
          : IndexedStack(
              index: _tab,
              children: const [ProjectsContent(), SessionScreen()],
            ),
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: _tab,
              onTap: _selectTab,
              selectedItemColor: const Color(0xFF6750A4),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.folder),
                  label: 'Projects',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.shield),
                  label: 'Sessions',
                ),
              ],
            )
          : null,
    );
  }
}
