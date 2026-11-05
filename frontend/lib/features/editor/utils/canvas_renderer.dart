import 'package:flutter/material.dart';

import '../constants/diagram_constants.dart';
import '../models/editor_models.dart';
import 'diagram_scene.dart';

class SceneCanvasRenderer {
  static void drawGrid(Canvas canvas, GridScene grid) {
    final linePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;
    for (final l in grid.lines) {
      canvas.drawLine(l.from, l.to, linePaint);
    }

    final style = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    );
    for (final lab in grid.labels) {
      final tp = TextPainter(
        text: TextSpan(text: lab.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = lab.isColumn
          ? Offset(lab.position.dx - tp.width / 2, lab.position.dy)
          : Offset(lab.position.dx, lab.position.dy - tp.height / 2);
      tp.paint(canvas, pos);
    }
  }

  static void drawConnections(
    Canvas canvas,
    DiagramScene scene, {
    String? selectedConnectionId,
    String? hoveredConnectionId,
  }) {
    final hasHover = hoveredConnectionId != null;
    for (final item in scene.connections) {
      final isHovered = item.connection.id == hoveredConnectionId;
      final isSelected = item.connection.id == selectedConnectionId;
      final isDimmed = hasHover && !isHovered;

      final color = isHovered || isSelected
          ? Colors.blue
          : isDimmed
          ? Colors.grey.shade800.withValues(alpha: 0.5)
          : Colors.black;
      final width = isHovered || isSelected ? 4.0 : 2.0;

      final strokePaint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      canvas.drawPath(item.path, strokePaint);

      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      for (final a in item.arrows) {
        _drawArrowHead(canvas, a.tip, a.direction, arrowPaint);
      }
    }
  }

  static void drawInsertionPoints(Canvas canvas, List<InsertionPoint> points) {
    for (final point in points) {
      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        point.position,
        InsertionPointConstants.radius,
        fillPaint,
      );
      final strokePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = InsertionPointConstants.strokeWidth;
      canvas.drawCircle(
        point.position,
        InsertionPointConstants.radius,
        strokePaint,
      );
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

  static void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset dir,
    Paint paint,
  ) {
    const arrowLen = 11.0;
    const halfWidth = 5.0;
    final len = dir.distance;
    if (len < 1e-4) return;
    final ux = dir.dx / len;
    final uy = dir.dy / len;

    final baseX = tip.dx - ux * arrowLen;
    final baseY = tip.dy - uy * arrowLen;
    final px = -uy * halfWidth;
    final py = ux * halfWidth;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseX + px, baseY + py)
      ..lineTo(baseX - px, baseY - py)
      ..close();
    canvas.drawPath(path, paint);
  }
}
