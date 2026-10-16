import 'package:flutter/material.dart';

import '../../../core/navigation/last_route_storage.dart';
import '../widgets/sidebar.dart';
import 'screens.dart';
import 'sessions.dart';
import 'project_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
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
    final storage = LastRouteStorage.instance;
    _tab = storage.tab == LastRouteStorage.routeSessions
        ? _sessions
        : _projects;

    final pid = storage.projectId;
    if (pid != null) {
      _drillDownActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushProject(pid));
    }
    // WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDrillDown());
  }

  Future<void> _pushProject(int projectId) async {
    if (!mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => ProjectScreen(
          projectId: projectId,
          restoreFlowchartId: LastRouteStorage.instance.flowchartId,
        ),
      ),
    );

    // await Navigator.of(context).push(
    //   MaterialPageRoute(
    //     builder: (_) => ProjectScreen(
    //       projectId: projectId,
    //       restoreFlowchartId: LastRouteStorage.instance.flowchartId,
    //     ),
    //   ),
    // );

    if (!mounted) return;
    // Пользователь вернулся из проекта
    setState(() => _drillDownActive = false);
  }

  // Future<void> _restoreDrillDown() async {
  //   final storage = LastRouteStorage.instance;
  //   final projectId = storage.projectId;
  //   if (projectId == null || !mounted) return;

  //   await Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (_) => ProjectScreen(
  //         projectId: projectId,
  //         restoreFlowchartId:
  //             storage.flowchartId, // null, если редактор не был открыт
  //       ),
  //     ),
  //   );
  // }

  Future<void> _selectTab(int index) async {
    if (_tab == index) return;
    setState(() => _tab = index);
    await LastRouteStorage.instance.setTab(
      index == _sessions
          ? LastRouteStorage.routeSessions
          : LastRouteStorage.routeProjects,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(currentIndex: _tab, onSelect: _selectTab),
          Expanded(
            child: _drillDownActive
                ? const SizedBox.shrink()
                : IndexedStack(
                    index: _tab,
                    children: const [ProjectsContent(), SessionScreen()],
                  ),
            // child: IndexedStack(
            //   index: _tab,
            //   children: const [ProjectsContent(), SessionScreen()],
            // ),
          ),
        ],
      ),
    );
  }
}
