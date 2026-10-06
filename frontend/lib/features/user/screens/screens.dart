import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/top_bar.dart';
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
    //TODO
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
                TopBar(onNewProject: _createProject),

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
                                  return ProjectCard(
                                    project: projects[index],
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

