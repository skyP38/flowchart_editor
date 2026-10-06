import 'package:flutter/material.dart';
import '../models/project.dart';
import '../screens/project_screen.dart';

class ProjectCard extends StatelessWidget {
  final Project project;

  const ProjectCard({
    super.key,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),

      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return ProjectScreen(
                projectId: project.id,
              );
            },
          ),
        );
      },

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFD9D9D9),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF9FAFB),
              ),
            ),

            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
 }
