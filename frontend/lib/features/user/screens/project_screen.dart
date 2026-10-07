import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../models/project.dart';
import '../models/flowchart.dart';
import '../services/api_service.dart';
import '../widgets/card_f.dart';

class ProjectScreen extends StatefulWidget {
  final int projectId;

  const ProjectScreen({super.key, required this.projectId});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final ApiService _api = ApiService();
  late Future<Project> _projectFuture;

  @override
  void initState() {
    super.initState();
    _reload();
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
    await _api.deleteFlowchart(id);
    _reload();
  }

  void _openFlowchart(Flowchart f) {
    //TODO
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          const Sidebar(currentRoute: 'projects'),
          Expanded(
            child: FutureBuilder<Project>(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Project project) {
    return Column(
      children: [        Container(
          height: 73,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My projects / ${project.name}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),

              Row(
                children: [
                  Container(
                    width: 280,
                    height: 37,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                        SizedBox(width: 8),
                        Text(
                          'Search for flowchart...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
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
                    ? const Center(child: Text('There are not flowcharts yet'))
                    : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
 
