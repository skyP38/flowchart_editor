import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/card_p.dart';
import '../models/project.dart';
import '../services/api_service.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final ApiService _api = ApiService();
  late Future<List<Project>> _projects;

  @override
  void initState() {
    super.initState();
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
  
  Future<void> _deleteProject(Project project) async {
    await _api.deleteProject(project.id);
    _reload();
  } 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Sidebar(currentRoute: 'projects'),

          Expanded(
            child: Column(
              children: [
		Padding(
                  padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 380,
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
                              'Search for project...',
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
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 24),

                        Expanded(
                          child: FutureBuilder<List<Project>>(
                            future: _projects,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
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
                              final projects = snapshot.data ?? [];
                              if (projects.isEmpty) {
                                return const Center(
                                  child: Text('There are no projects yet'),
                                );
                              }
                              return GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                  childAspectRatio: 418 / 217,
                                ),
                                itemCount: projects.length,
                                itemBuilder: (context, index) {
                                  final project = projects[index];
                                  return ProjectCard(
                                    project: project,
                                    onDelete: () => _deleteProject(project),
                                  );
                                },
                              );
                            },
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
    );
  }
}

