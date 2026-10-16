import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';

class InsertionPointsService {
  final ConnectionRouter router;
  const InsertionPointsService({required this.router});

  List<InsertionPoint> compute(FlowchartGraph g) {
    final points = <InsertionPoint>[];
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      final path = router.build(conn, g);
      Offset? plusPos;
      // Для no - гарантированно первый вертикальный сегмент
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
      }
      plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
      if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
    }
    return points;
  }

  Offset? _midOfPath(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.length <= 0.1) continue;
      final t = metric.getTangentForOffset(metric.length / 2);
      if (t != null) return t.position;
    }
    return null;
  }

  Offset? _firstVerticalMidpoint(Path path) {
    final samples = <Offset>[];
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += 1) {
        final t = metric.getTangentForOffset(d);
        if (t != null) samples.add(t.position);
      }
    }
    if (samples.length < 2) return null;

    for (int i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      final isVertical = (a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() > 0.5;
      if (!isVertical) continue;

      int endIdx = i;
      while (endIdx < samples.length - 1) {
        final p = samples[endIdx];
        final q = samples[endIdx + 1];
        final stillVertical =
            (p.dx - q.dx).abs() < 0.5 && (p.dy - q.dy).abs() > 0.5;
        if (!stillVertical) break;
        endIdx++;
      }

      final top = samples[i - 1];
      final bottom = samples[endIdx];
      return Offset(top.dx, (top.dy + bottom.dy) / 2);
    }
    return null;
  }
}
