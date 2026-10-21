import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';
import 'dart:math' as math;

class InsertionPointsService {
  final ConnectionRouter router;
  const InsertionPointsService({required this.router});

  List<InsertionPoint> compute(FlowchartGraph g) {
    // Шаг 1: для каждого target собираем точки вливания no-путей
    // (по последнему горизонтальному сегменту пути)
    final noMergesByTarget = <String, List<_MergePoint>>{};
    for (final conn in g.connections) {
      if (conn.sourcePort != 'no') continue;
      if (conn.id == null) continue;
      final path = router.build(conn, g);
      final mergeY = _lastHorizontalY(path);
      if (mergeY != null) {
        noMergesByTarget
            .putIfAbsent(conn.targetNodeName, () => [])
            .add(_MergePoint(y: mergeY, connId: conn.id!));
      }
    }

    // Шаг 2: обрабатываем каждую связь
    final points = <InsertionPoint>[];
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      final path = router.build(conn, g);
      if (path.computeMetrics().isEmpty) continue;

      // yes/out с вливанием no-пути -> разбиваем на до/после слияния
      _MergePoint? mergeOnPath;
      if (conn.sourcePort == 'yes' || conn.sourcePort == 'out') {
        final merges = noMergesByTarget[conn.targetNodeName];
        if (merges != null) {
          final samples = _samplePath(path);
          _MergePoint? best;
          for (final m in merges) {
            final onPath = samples.any((p) => (p.dy - m.y).abs() < 1.0);
            if (onPath && (best == null || m.y > best.y)) best = m;
          }
          mergeOnPath = best;
        }
      }

      if (mergeOnPath != null) {
        final before = _midpointBeforeY(path, mergeOnPath.y);
        final after = _midpointAfterY(path, mergeOnPath.y);
        if (before != null) points.add(InsertionPoint(before, conn));
        if (after != null) {
          points.add(
            InsertionPoint(
              after,
              conn,
              isAfterMerge: true,
              mergeOtherConnId: mergeOnPath.connId,
            ),
          );
        }
        continue;
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
      } else if (conn.sourcePort == 'exit') {
        plusPos = _endOfHorizontalSegment(path);
      }
      plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
      if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
    }
    return points;
  }

  double? _lastHorizontalY(Path path) {
    final segs = _extractSegments(path);
    for (final s in segs.reversed) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (isHorz) return s.start.dy;
    }
    return null;
  }

  Offset? _midpointBeforeY(Path path, double y) {
    final s = _samplePath(path).where((p) => p.dy < y - 0.5).toList();
    if (s.isEmpty) return null;
    return s[s.length ~/ 2];
  }

  Offset? _midpointAfterY(Path path, double y) {
    final s = _samplePath(path).where((p) => p.dy > y + 0.5).toList();
    if (s.isEmpty) return null;
    return s[s.length ~/ 2];
  }

  List<Offset> _samplePath(Path path) {
    final out = <Offset>[];
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += 1) {
        final t = metric.getTangentForOffset(d);
        if (t != null) out.add(t.position);
      }
    }
    return out;
  }

  List<_Seg> _extractSegments(Path path) {
    final samples = _samplePath(path);
    final segs = <_Seg>[];
    if (samples.length < 2) return segs;

    _Seg cur = _Seg(samples[0], samples[0]);
    for (int i = 1; i < samples.length; i++) {
      final a = samples[i - 1], b = samples[i];
      final sameX = (a.dx - b.dx).abs() < 0.5;
      final sameY = (a.dy - b.dy).abs() < 0.5;
      final isHorz = sameY && !sameX;
      final isVert = sameX && !sameY;
      final curHorz =
          (cur.start.dy - cur.end.dy).abs() < 0.5 &&
          (cur.start.dx - cur.end.dx).abs() > 0.5;
      final curVert =
          (cur.start.dx - cur.end.dx).abs() < 0.5 &&
          (cur.start.dy - cur.end.dy).abs() > 0.5;
      if ((curHorz && isHorz) || (curVert && isVert) || cur.start == cur.end) {
        cur = _Seg(cur.start, b);
      } else {
        if (cur.start != cur.end) segs.add(cur);
        cur = _Seg(a, b);
      }
    }
    if (cur.start != cur.end) segs.add(cur);
    return segs;
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
    final samples = _samplePath(path);
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

  Offset? _endOfHorizontalSegment(Path path) {
    Offset? lastCorner;
    for (final metric in path.computeMetrics()) {
      bool wasHorizontal = false;
      for (double d = 0; d <= metric.length; d += 1) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        final v = t.vector;
        final isVert = v.dx.abs() < 0.5 && v.dy.abs() > 0.5;
        final isHorz = v.dx.abs() > 0.5 && v.dy.abs() < 0.5;
        if (isHorz) {
          wasHorizontal = true;
        } else if (isVert && wasHorizontal) {
          lastCorner = t.position;
          wasHorizontal = false;
        }
      }
    }
    return lastCorner;
  }
}

class _MergePoint {
  final double y;
  final String connId;
  const _MergePoint({required this.y, required this.connId});
}

class _Seg {
  final Offset start;
  final Offset end;
  const _Seg(this.start, this.end);
}
