import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_service.dart';
import '../widgets/card_p.dart';
import '../models/project.dart';
import 'project_screen.dart';

class ProjectsContent extends StatefulWidget {
  const ProjectsContent({super.key});

  @override
  State<ProjectsContent> createState() => _ProjectsContentState();
}

class _ProjectsContentState extends State<ProjectsContent> {
  late final ApiService _api;
  late Future<List<Project>> _projects;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiService>();
    _projects = _api.listProjects();
  }

  void _reload() {
    setState(() {
      _projects = _api.listProjects();
    });
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Name project'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await _api.createProject(name);
    _reload();
  }

  Future<void> _openProject(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectScreen(projectId: project.id)),
    );
    if (mounted) _reload();
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'Delete "${project.name}" and all its flowcharts? '
          'This action cannot be undone.',
        ),
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
      await _api.deleteProject(project.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "${project.name}" deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete project: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 800;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 12 : 40,
            narrow ? 16 : 24,
            narrow ? 12 : 40,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    height: 37,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                        SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (value) {
                              setState(() {
                                _search = value;
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search for project...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
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
                onTap: _createProject,
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
                        'New project',
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My project',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: FutureBuilder<List<Project>>(
                    future: _projects,
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
                      final projects = snapshot.data ?? <Project>[];
                      final query = _search.trim().toLowerCase();

                      final filteredProjects = projects
                          .where((project) {
                            return project.name.toLowerCase().contains(query);
                          })
                          .toList(growable: false);
                      if (projects.isEmpty) {
                        return const Center(
                          child: Text('There are no projects yet'),
                        );
                      }

                      if (filteredProjects.isEmpty) {
                        return const Center(
                          child: Text('No projects match your search'),
                        );
                      }
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.sizeOf(context).width < 800
                              ? 1
                              : 2,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                          childAspectRatio: 418 / 217,
                        ),
                        itemCount: filteredProjects.length,
                        itemBuilder: (context, index) {
                          final project = filteredProjects[index];
                          return InkWell(
                            onTap: () => _openProject(project),
                            borderRadius: BorderRadius.circular(12),
                            child: ProjectCard(
                              project: project,
                              onDelete: () => _deleteProject(project),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // ],
                // ),
                // ),
                // ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
