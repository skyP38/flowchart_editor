import 'package:flutter/material.dart';
import '../constants/diagram_constants.dart';
import '../domain/connection_router.dart';
import '../domain/flowchart_graph.dart';
import '../models/editor_models.dart';

// Рисует все соединения между блоками и "+" на связи при добавлении элемента
class ConnectionPainter extends CustomPainter {
  final FlowchartGraph graph;
  final ConnectionRouter router;
  final String? selectedConnectionId;
  final List<InsertionPoint> insertionPoints;

  ConnectionPainter({
    required this.graph,
    required this.router,
    this.selectedConnectionId,
    required this.insertionPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final conn in graph.connections) {
      final isSelected = conn.id != null && conn.id == selectedConnectionId;
      final paint = Paint()
        ..color = isSelected ? Colors.blue : Colors.black
        ..strokeWidth = isSelected ? 4 : 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(router.build(conn, graph), paint);
    }

    // Кружки для вставки блоков
    for (final point in insertionPoints) {
      // Заливка кружка
      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        point.position,
        InsertionPointConstants.radius,
        fillPaint,
      );
      // Обводка
      final strokePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = InsertionPointConstants.strokeWidth;
      canvas.drawCircle(
        point.position,
        InsertionPointConstants.radius,
        strokePaint,
      );
      // Плюс
      final plusPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = InsertionPointConstants.strokeWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        point.position + Offset(-InsertionPointConstants.plusSize, 0),
        point.position + Offset(InsertionPointConstants.plusSize, 0),
        plusPaint,
      );
      canvas.drawLine(
        point.position + Offset(0, -InsertionPointConstants.plusSize),
        point.position + Offset(0, InsertionPointConstants.plusSize),
        plusPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return !identical(oldDelegate.graph, graph) ||
        oldDelegate.selectedConnectionId != selectedConnectionId ||
        !identical(oldDelegate.insertionPoints, insertionPoints);
  }
}
