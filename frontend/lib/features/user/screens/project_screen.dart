import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_service.dart';
import '../../../core/navigation/last_route_storage.dart';

// import '../widgets/sidebar.dart';
import '../models/project.dart';
import '../models/flowchart.dart';
import '../widgets/card_f.dart';

import 'flowchart_editor_page.dart';

class ProjectScreen extends StatefulWidget {
  final int projectId;
  final int? restoreFlowchartId;

  const ProjectScreen({
    super.key,
    required this.projectId,
    this.restoreFlowchartId,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final ApiService _api;
  late Future<Project> _projectFuture;
  final _storage = LastRouteStorage.instance;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[ProjectScreen] init pid=${widget.projectId} '
      'restore=${widget.restoreFlowchartId}',
    );
    _api = context.read<ApiService>();
    _projectFuture = _api.getProject(widget.projectId);
    _storage.setProject(widget.projectId);
    final fid = widget.restoreFlowchartId;
    if (fid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[ProjectScreen] pushing editor($fid)');
        // _restoreFlowchartEditor(fid);
        // if (!mounted) return;
        _openFlowchartEditor(fid);
      });
    }
    // _reload();
  }

  @override
  void dispose() {
    // Выход из проекта — стираем всё, что было открыто поверх.
    _storage.setProject(null);
    super.dispose();
  }

  Future<void> _openFlowchartEditor(int flowchartId) async {
    await _storage.setFlowchart(flowchartId);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlowchartEditorPage(
          projectId: widget.projectId,
          flowchartId: flowchartId,
        ),
      ),
    );

    // Редактор закрыт
    await _storage.setFlowchart(null);
  }

  // все тапы по карточкам идут через это
  void _openFlowchart(Flowchart f) => _openFlowchartEditor(f.id);

  void _reload() {
    setState(() {
      _projectFuture = _api.getProject(widget.projectId);
    });
  }

  Future<void> _createFlowchart() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New flowchart'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Name flowchart'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await _api.createFlowchart(widget.projectId, name);
    _reload();
  }

  Future<void> _deleteFlowchart(int id) async {
    await _api.deleteFlowchart(widget.projectId, id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('My projects / ...'), // ← breadcrumb можно сюда
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      // body.: Row(
      // children: [
      //   const Sidebar(currentRoute: 'projects'),
      //   Expanded(
      //     child:
      body: FutureBuilder<Project>(
        future: _projectFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _reload,
                    child: const Text('Repeat'),
                  ),
                ],
              ),
            );
          }

          final project = snapshot.data!;
          return _buildContent(project);
        },
        // ),
        // ),
        // ],
      ),
    );
  }

  Widget _buildContent(Project project) {
    return Column(
      children: [
        Container(
          height: 73,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'My projects / ${project.name}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 180),
                        child: Container(
                          // width: 280,
                          height: 37,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                size: 18,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Search for flowchart...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    InkWell(
                      onTap: _createFlowchart,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 37,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6750A4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'New flowchart',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${project.flowcharts.length} flowcharts',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: project.flowcharts.isEmpty
                      ? const Center(
                          child: Text('There are not flowcharts yet'),
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 24,
                                mainAxisSpacing: 24,
                                childAspectRatio: 418 / 217,
                              ),
                          itemCount: project.flowcharts.length,
                          itemBuilder: (context, index) {
                            final f = project.flowcharts[index];
                            return FlowchartCard(
                              flowchart: f,
                              onTap: () => _openFlowchart(f),
                              onDelete: () => _deleteFlowchart(f.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
