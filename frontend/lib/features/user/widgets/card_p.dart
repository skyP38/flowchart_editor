import 'package:flutter/material.dart';
import '../models/project.dart';
import '../screens/project_screen.dart';

class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback? onDelete;

  const ProjectCard({super.key, required this.project, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),

      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return ProjectScreen(projectId: project.id);
            },
          ),
        );
      },

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD9D9D9)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF9FAFB),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    // ← ключевое
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),

                  // Expanded(
                  //   flex: 2,
                  //   child: Padding(
                  //     padding: const EdgeInsets.all(20),
                  //     child: Column(
                  //       children: [
                  //         Row(
                  //           mainAxisAlignment:
                  //               MainAxisAlignment.spaceBetween,
                  //           children: [
                  //             Text(
                  //               project.name,
                  //               style: const TextStyle(
                  //                 fontSize: 16,
                  //                 fontWeight: FontWeight.w600,
                  //               ),
                  //             ),
                  //             const SizedBox(width: 8),
                  //             InkWell(
                  //               onTap: onDelete,
                  //               borderRadius: BorderRadius.circular(6),
                  //               child: Container(
                  //                 width: 26,
                  //                 height: 26,
                  //                 decoration: BoxDecoration(
                  //                   color: const Color(0xFFFEE2E2),
                  //                   borderRadius: BorderRadius.circular(6),
                  //                 ),
                  //                 child: const Icon(
                  //                   Icons.delete_outline,
                  //                   size: 14,
                  //                   color: Color(0xFFEF4444),
                  //                 ),
                  //               ),
                  //             ),
                  //           ],
                  //         ),
                ],
              ),
            ),
            // ),
          ],
        ),
      ),
    );
  }
}
