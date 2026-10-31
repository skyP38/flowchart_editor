import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../factories/node_factory.dart';
import '../models/flow_models.dart';
import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';

class InsertionPointsService {
  final ConnectionRouter router;
  const InsertionPointsService({required this.router});

  List<InsertionPoint> compute(FlowchartGraph g) {
    final points = <InsertionPoint>[];

    // Все target с >= 2 входящими non-loopback
    final incomingByTarget = <String, List<ConnectionData>>{};
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      incomingByTarget.putIfAbsent(conn.targetNodeName, () => []).add(conn);
    }

    // Для каждого merge-target вычисляем точку слияния
    final mergeInfoByTarget = <String, _MergeInfo>{};
    for (final e in incomingByTarget.entries) {
      if (e.value.length < 2) continue;
      final target = g.nodes[e.key];
      if (target == null) continue;
      final info = _computeMergeInfo(g, e.value, target);
      if (info != null) mergeInfoByTarget[e.key] = info;
    }

    for (final conn in g.connections) {
      final isBodyLoopback =
          conn.targetPort == 'loopback' &&
          (conn.sourcePort == 'body' || conn.sourcePort == 'out') &&
          g.nodes[conn.targetNodeName]?.data is ForBlock;
      if (conn.targetPort == 'loopback' && !isBodyLoopback) continue;
      final routed = router.build(conn, g);
      final path = routed.path;
      if (path.computeMetrics().isEmpty) continue;

      if (conn.sourcePort == 'exit') {
        final src = g.nodes[conn.sourceNodeName];
        final plusPos = src != null
            ? _exitPlusPosition(path, src)
            : (_firstVerticalMidpoint(path) ?? _midOfPath(path));
        if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
        continue;
      }

      if (conn.sourcePort == 'yes') {
        final src = g.nodes[conn.sourceNodeName];
        if (src == null) continue;

        final centerX = src.position.dx + router.nodeSize.width / 2;
        final exitY = src.position.dy + router.nodeSize.height;

        final firstVertMid = _firstVerticalMidpoint(path);
        final y1 = firstVertMid?.dy;

        double? y2;
        final mergeInfo = mergeInfoByTarget[conn.targetNodeName];
        if (mergeInfo != null) {
          final noConn = mergeInfo.incoming.firstWhereOrNull(
            (c) =>
                c.sourcePort == 'no' && c.sourceNodeName == conn.sourceNodeName,
          );
          if (noConn != null) {
            final noPath = router.build(noConn, g).path;
            final intersectionY = _lastHorizontalY(noPath);
            if (intersectionY != null && intersectionY > exitY + 1.0) {
              y2 = (exitY + intersectionY) / 2;
            }
          }
          y2 ??= (exitY + mergeInfo.mergeY) / 2;
        }

        double? y;
        if (y1 != null && y2 != null) {
          y = math.min(y1, y2);
        } else {
          y = y1 ?? y2;
        }

        if (y != null) {
          points.add(InsertionPoint(Offset(centerX, y), conn));
        }
        continue;
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
        if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
        continue;
      } else {
        plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
      }
      if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
    }

    //Для каждого merge-target - ровно один after
    for (final info in mergeInfoByTarget.values) {
      final otherIds = info.incoming
          .where((c) => c.id != null && c.id != info.deepestEdge.id)
          .map((c) => c.id!)
          .toList();
      final y = (info.maxLandingY + info.targetTop) / 2;
      points.add(
        InsertionPoint(
          Offset(info.centerX, y),
          info.deepestEdge,
          isAfterMerge: true,
          mergeOtherConnIds: otherIds,
        ),
      );
    }

    return points;
  }

  _MergeInfo? _computeMergeInfo(
    FlowchartGraph g,
    List<ConnectionData> incoming,
    NodeModel target,
  ) {
    final centerX = target.position.dx + router.nodeSize.width / 2;
    final targetTop = target.position.dy;

    debugPrint(
      '[merge] target=${target.name} '
      'centerX=$centerX targetTop=$targetTop '
      'inputs=${incoming.length}',
    );
    
    double? maxLandingY;
    ConnectionData? deepestEdge;
    for (final conn in incoming) {
      final routed = router.build(conn, g);
      final path = routed.path;
      if (path.computeMetrics().isEmpty) {
        debugPrint(
          '[merge]   ${conn.sourceNodeName}--${conn.sourcePort}-->'
          '${conn.targetNodeName}: path EMPTY',
        );
        continue;
      }
      final y = _landingYAt(path, centerX, targetTop);
         debugPrint(
        '[merge]   ${conn.sourceNodeName}--${conn.sourcePort}-->'
        '${conn.targetNodeName}: landingY=$y',
      );
      if (y != null && (maxLandingY == null || y > maxLandingY)) {
        maxLandingY = y;
        deepestEdge = conn;
      }
    }
    if (maxLandingY == null || deepestEdge == null) {
      debugPrint(
        '[merge] target=${target.name}: NO MERGE '
        '(all landings null)',
      );
      return null;
    }

    final gap = targetTop - maxLandingY;
    debugPrint(
      '[merge] target=${target.name}: '
      'maxLandingY=$maxLandingY gap=$gap '
      'deepest=${deepestEdge.sourceNodeName}--${deepestEdge.sourcePort}',
    );

    if (gap < 5) {
      debugPrint('[merge] target=${target.name}: NO MERGE (gap < 5)');
      return null;
    }

    return _MergeInfo(
      incoming: incoming,
      deepestEdge: deepestEdge,
      maxLandingY: maxLandingY,
      targetTop: targetTop,
      centerX: centerX,
    );
  }

  double? _landingYAt(Path path, double centerX, double targetTop) {
    final samples = _samplePath(path);
    double? best;
    for (final p in samples) {
      if ((p.dx - centerX).abs() > 1.0) continue;
      if (p.dy >= targetTop - 1.0) continue;
      if (best == null || p.dy < best) best = p.dy;
    }
    return best;
  }

  /// Плюс на exit-ветке
  Offset? _exitPlusPosition(Path path, NodeModel src) {
    final srcCenterX = src.position.dx + router.nodeSize.width / 2;
    final segs = _extractSegments(path);
    if (segs.isEmpty) return null;

    final horzs = <_Seg>[];
    for (final s in segs) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (isHorz) horzs.add(s);
    }
    if (horzs.isEmpty) return null;

    _Seg? covering;
    for (final s in horzs) {
      final xLo = math.min(s.start.dx, s.end.dx);
      final xHi = math.max(s.start.dx, s.end.dx);
      if (srcCenterX >= xLo - 0.5 && srcCenterX <= xHi + 0.5) {
        covering = s;
      }
    }

    final target = covering ?? horzs.last;
    debugPrint(
      '[exit+] srcCenterX=$srcCenterX covering=${covering != null} '
      'y=${target.start.dy} '
      'xRange=[${math.min(target.start.dx, target.end.dx)},'
      '${math.max(target.start.dx, target.end.dx)}]',
    );
    return Offset(srcCenterX, target.start.dy);
  }

  /// Y последнего горизонтального сегмента пути
  double? _lastHorizontalY(Path path) {
    final segs = _extractSegments(path);
    double? y;
    for (final s in segs) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (isHorz) y = s.start.dy;
    }
    return y;
  }

  //  Общие хелперы
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
}

class _MergeInfo {
  final List<ConnectionData> incoming;
  final ConnectionData deepestEdge;
  final double maxLandingY;
  final double targetTop;
  final double centerX;
  double get mergeY => maxLandingY;
  const _MergeInfo({
    required this.incoming,
    required this.deepestEdge,
    required this.maxLandingY,
    required this.targetTop,
    required this.centerX,
  });
}

class _Seg {
  final Offset start;
  final Offset end;
  const _Seg(this.start, this.end);
}
