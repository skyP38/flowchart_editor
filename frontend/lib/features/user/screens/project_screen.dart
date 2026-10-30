import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_service.dart';
import '../../../core/navigation/last_route_storage.dart';

import '../models/project.dart';
import '../models/flowchart.dart';
import '../widgets/card_f.dart';
import 'flowchart_editor_page.dart';
import '../widgets/user.dart';

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
  String _search = '';
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
        _openFlowchartEditor(fid);
      });
    }
  }

  @override
  void dispose() {
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
    if (mounted) {
      _reload();
    }
  }

  // все тапы по карточкам идут через это
  void _openFlowchart(Flowchart f) => _openFlowchartEditor(f.id);

  Future<void> _renameFlowchart(Flowchart f) async {
    final controller = TextEditingController(text: f.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать блок-схему'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Новое название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == f.name) return;

    try {
      await _api.renameFlowchart(widget.projectId, f.id, newName);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка переименования: $e')));
    }
  }

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
    final project = await _projectFuture;
    final target = project.flowcharts.where((f) => f.id == id).firstOrNull;
    final name = target?.name ?? 'this flowchart';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete flowchart?'),
        content: Text('Delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.deleteFlowchart(widget.projectId, id);
      if (mounted) _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete flowchart: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return FutureBuilder<Project>(
      future: _projectFuture,
      builder: (context, snapshot) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text("My projects"),
            titleTextStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E1E1E),
            ),
            actions: [
              UserChip(compact: narrow),
              const SizedBox(width: 8),
            ],
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          body: _buildBody(snapshot),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<Project> snapshot) {
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
            ElevatedButton(onPressed: _reload, child: const Text('Repeat')),
          ],
        ),
      );
    }
    return _buildContent(snapshot.data!);
  }

  Widget _buildContent(Project project) {
    final narrow = MediaQuery.sizeOf(context).width < 800;
    final query = _search.trim().toLowerCase();

    final flowcharts = project.flowcharts
        .where((flowchart) {
          return flowchart.name.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Column(
      children: [
        _buildHeader(project, narrow),
        Expanded(
          child: Container(
            padding: EdgeInsets.all(narrow ? 16 : 40),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: narrow ? 20 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Text(
                        '${flowcharts.length} flowcharts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: project.flowcharts.isEmpty
                      ? const Center(child: Text('There are no flowcharts yet'))
                      : flowcharts.isEmpty
                      ? const Center(
                          child: Text('No flowcharts match your search'),
                        )
                      : GridView.builder(
                          gridDelegate: narrow
                              ? const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 1,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1,
                                )
                              : const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 340,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 20,
                                  childAspectRatio: 1,
                                ),
                          itemCount: flowcharts.length,
                          itemBuilder: (context, index) {
                            final f = flowcharts[index];

                            return FlowchartCard(
                              flowchart: f,
                              onTap: () => _openFlowchart(f),
                              onDelete: () => _deleteFlowchart(f.id),
                              onRename: () => _renameFlowchart(f),
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

  Widget _buildHeader(Project project, bool narrow) {
    final searchBox = Container(
      height: 37,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: 'Search for flowchart...',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );

    final newButton = InkWell(
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
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
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
    );

    if (narrow) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            searchBox,
            const SizedBox(height: 8),
            newButton,
          ],
        ),
      );
    }

    return Container(
      height: 73,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 180),
                    child: searchBox,
                  ),
                ),
                const SizedBox(width: 16),
                newButton,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
