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
  final String? hoveredConnectionId;
  final List<InsertionPoint> insertionPoints;

  ConnectionPainter({
    required this.graph,
    required this.router,
    this.selectedConnectionId,
    this.hoveredConnectionId,
    required this.insertionPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasHover = hoveredConnectionId != null;
    for (final conn in graph.connections) {
      final isHovered = conn.id == hoveredConnectionId;
      final isDimmed = hasHover && !isHovered;

      final isSelected = conn.id != null && conn.id == selectedConnectionId;

      final color = isHovered
          ? Colors.blue
          : isDimmed
          ? Colors.grey.shade800.withValues(alpha: 0.5)
          : isSelected
          ? Colors.blue
          : Colors.black;
      final width = isHovered || isSelected
          ? 4.0
          // : isDimmed
          // ? 1.0
          : 2.0;

      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      final path = router.build(conn, graph);
      canvas.drawPath(path, paint);
      // canvas.drawPath(router.build(conn, graph), paint);

      _drawArrowsOnPath(
        canvas,
        path,
        paint,
        isLoopback: conn.targetPort == 'loopback',
      );
    }

    // Кружки для вставки блоков
    for (final point in insertionPoints) {
      final isPointOfHovered = point.connection.id == hoveredConnectionId;
      final plusColor = hasHover && !isPointOfHovered
          ? Colors.grey.shade400
          : Colors.blue;
      // Заливка кружка
      final fillPaint = Paint()
        ..color =
            plusColor //olors.white
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

  void _drawArrowsOnPath(
    Canvas canvas,
    Path path,
    Paint basePaint, {
    required bool isLoopback,
  }) {
    final segments = _extractSegments(path);
    if (segments.isEmpty) return;

    final arrowPaint = Paint()
      ..color = basePaint.color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      final isLast = i == segments.length - 1;
      final isHorizontal = s.dirY.abs() < 0.1;
      final goesLeft = s.dirX < -0.5;
      final segLen = (s.end - s.start).distance;
      if (segLen < 12) continue;

      // Стрелка в конце пути:
      // - loopback - всегда (входит в левую грань For);
      // - остальные - только если последний отрезок уходит влево.
      if (isLast && (isLoopback || goesLeft)) {
        _drawArrowHead(canvas, s.end, Offset(s.dirX, s.dirY), arrowPaint);
      }

      // Дополнительная стрелка на длинном левом горизонтальном отрезке:
      // середина петли loopback, горизонтальные обходы в _routeNo,
      // левый ход между колонками в _routeDefault.
      if (!isLast && isHorizontal && goesLeft && segLen > 30) {
        final mid = Offset(
          s.start.dx + (s.end.dx - s.start.dx) * 0.25,
          s.start.dy + (s.end.dy - s.start.dy) * 0.25,
        );
        //   (s.start.dx + s.end.dx) / 2,
        //   (s.start.dy + s.end.dy) / 2,
        // );
        _drawArrowHead(canvas, mid, Offset(s.dirX, s.dirY), arrowPaint);
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset dir, Paint paint) {
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

    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseX + px, baseY + py)
      ..lineTo(baseX - px, baseY - py)
      ..close();
    canvas.drawPath(arrow, paint);
  }

  // Разбивает Path на отрезки по смене направления.
  List<_Seg> _extractSegments(Path path) {
    final result = <_Seg>[];
    for (final metric in path.computeMetrics()) {
      _Seg? cur;
      for (double d = 0; d < metric.length; d += 2.0) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        final v = t.vector;
        final vl = v.distance;
        if (vl < 1e-4) continue;
        final nx = v.dx / vl;
        final ny = v.dy / vl;

        if (cur == null) {
          cur = _Seg(start: t.position, end: t.position, dirX: nx, dirY: ny);
          result.add(cur);
        } else if ((cur.dirX - nx).abs() > 0.05 ||
            (cur.dirY - ny).abs() > 0.05) {
          cur.end = t.position;
          cur = _Seg(start: t.position, end: t.position, dirX: nx, dirY: ny);
          result.add(cur);
        } else {
          cur.end = t.position;
        }
      }
      if (metric.length > 0 && cur != null) {
        final tEnd = metric.getTangentForOffset(metric.length);
        if (tEnd != null) cur.end = tEnd.position;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return !identical(oldDelegate.graph, graph) ||
        oldDelegate.selectedConnectionId != selectedConnectionId ||
        !identical(oldDelegate.insertionPoints, insertionPoints);
  }
}

class _Seg {
  final Offset start;
  Offset end;
  final double dirX;
  final double dirY;
  _Seg({
    required this.start,
    required this.end,
    required this.dirX,
    required this.dirY,
  });
}
