import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import '../utils/diagram_scene.dart';
import '../utils/canvas_renderer.dart';

// Рисует все соединения между блоками и "+" на связи при добавлении элемента
class ConnectionPainter extends CustomPainter {
  final DiagramScene scene;
  final String? selectedConnectionId;
  final String? hoveredConnectionId;
  final List<InsertionPoint> insertionPoints;

  ConnectionPainter({
    required this.scene,
    this.selectedConnectionId,
    this.hoveredConnectionId,
    required this.insertionPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    SceneCanvasRenderer.drawGrid(canvas, scene.grid);
    SceneCanvasRenderer.drawConnections(
      canvas,
      scene,
      selectedConnectionId: selectedConnectionId,
      hoveredConnectionId: hoveredConnectionId,
    );
    SceneCanvasRenderer.drawInsertionPoints(canvas, insertionPoints);
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter old) =>
      !identical(old.scene, scene) ||
      old.selectedConnectionId != selectedConnectionId ||
      old.hoveredConnectionId != hoveredConnectionId ||
      !identical(old.insertionPoints, insertionPoints);
}
