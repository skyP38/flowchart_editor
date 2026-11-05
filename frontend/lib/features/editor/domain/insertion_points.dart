import 'dart:math' as math;
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
      // if (conn.targetPort == 'loopback' && !isBodyLoopback) continue;
      final isExitLoopback =
          conn.targetPort == 'loopback' && conn.sourcePort == 'exit';
      if (conn.targetPort == 'loopback' && !isBodyLoopback && !isExitLoopback) {
        continue;
      }
      final routed = router.build(conn, g);
      final path = routed.path;
      if (path.computeMetrics().isEmpty) continue;

      if (conn.sourcePort == 'exit') {
        final src = g.nodes[conn.sourceNodeName];
        final plusPos = src != null
            ? _exitPlusPosition(path, src, g)
            : (_firstVerticalMidpoint(path) ?? _midOfPath(path));
        if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
        continue;
      }

      if (conn.sourcePort == 'yes') {
        final src = g.nodes[conn.sourceNodeName];
        if (src == null) continue;

        const double offset = 20.0;
        final mergeNode = _findYesMergeTarget(
          g,
          conn.sourceNodeName,
          mergeInfoByTarget,
        );

        var placed = false;

        if (mergeNode != null) {
          final mergeInfo = mergeInfoByTarget[mergeNode]!;
          final lastEdge = _findLastYesEdge(g, conn.sourceNodeName, mergeNode);
          if (lastEdge != null && lastEdge.id != null) {
            final targetY = mergeInfo.mergeY - offset;
            final alreadyHas = points.any(
              (p) =>
                  p.connection.id == lastEdge.id &&
                  (p.position.dy - targetY).abs() < 5,
            );
            if (!alreadyHas) {
              final lastPath = router.build(lastEdge, g).path;
              final lastX = _pathXAtY(lastPath, targetY);
              if (lastX != null) {
                // final lastX = _pathXAtY(lastPath, targetY) ?? mergeInfo.centerX;
                debugPrint(
                  '[yesPlus] ${conn.sourceNodeName}--yes->${conn.targetNodeName}: '
                  'merge=$mergeNode '
                  'lastEdge=${lastEdge.sourceNodeName}.${lastEdge.sourcePort} '
                  'x=${lastX.toStringAsFixed(1)} '
                  'y=${targetY.toStringAsFixed(1)}',
                );
                points.add(InsertionPoint(Offset(lastX, targetY), lastEdge));
                // placed = true;
              } else {
                debugPrint(
                  '[yesPlus/beforeMerge FAILED] ${conn.sourceNodeName}--yes->'
                  '${conn.targetNodeName}: lastX null '
                  'edge=${lastEdge.sourceNodeName}.${lastEdge.sourcePort} '
                  'targetY=${targetY.toStringAsFixed(1)}',
                );
              }
            } else {
              final isOwnEdge =
                  lastEdge.sourceNodeName == conn.sourceNodeName &&
                  lastEdge.sourcePort == 'yes';

              if (isOwnEdge) {
                debugPrint(
                  '[yesPlus/beforeMerge DEDUP] ${conn.sourceNodeName}--yes->'
                  '${conn.targetNodeName}: '
                  'lastEdge=${lastEdge.sourceNodeName}.${lastEdge.sourcePort} '
                  'already placed (shared edge)',
                );
                placed = true;
              }
            }
          } else {
            debugPrint(
              '[yesPlus/beforeMerge FAILED] ${conn.sourceNodeName}--yes->'
              '${conn.targetNodeName}: lastEdge null for merge=$mergeNode',
            );
          }
        } else {
          debugPrint(
            '[yesPlus/noMerge] ${conn.sourceNodeName}--yes->'
            '${conn.targetNodeName}: no merge in yes branch',
          );
        }
        if (!placed) {
          final plusPos = _firstVerticalMidpoint(path) ?? _midOfPath(path);
          if (plusPos != null) {
            debugPrint(
              '[yesPlus/ownMidpoint] ${conn.sourceNodeName}--yes->'
              '${conn.targetNodeName}: '
              'x=${plusPos.dx.toStringAsFixed(1)} '
              'y=${plusPos.dy.toStringAsFixed(1)}',
            );
            points.add(InsertionPoint(plusPos, conn));
          } else {
            debugPrint(
              '[yesPlus/ownMidpoint FAILED] ${conn.sourceNodeName}--yes->'
              '${conn.targetNodeName}: midpoint null',
            );
          }
        }
        continue;
      }

      for (final entry in mergeInfoByTarget.entries) {
        final targetName = entry.key;
        final info = entry.value;

        final otherIds = info.incoming
            .where((c) => c.id != null && c.id != info.deepestEdge.id)
            .map((c) => c.id!)
            .toList();

        final afterY = (info.maxLandingY + info.targetTop) / 2;
        debugPrint(
          '[afterPlus] target=$targetName '
          'mergeY=${info.maxLandingY.toStringAsFixed(1)} '
          'targetTop=${info.targetTop.toStringAsFixed(1)} '
          'afterY=${afterY.toStringAsFixed(1)} '
          'deepest=${info.deepestEdge.sourceNodeName}.${info.deepestEdge.sourcePort} '
          'others=${otherIds.length}',
        );

        points.add(
          InsertionPoint(
            Offset(info.centerX, afterY),
            info.deepestEdge,
            isAfterMerge: true,
            mergeOtherConnIds: otherIds,
          ),
        );
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
        if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
        continue;
      } else if (conn.sourcePort == 'out' &&
          mergeInfoByTarget.containsKey(conn.targetNodeName)) {
        continue;
      } else {
        plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
      }
      if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
    }

    return points;
  }

  /// Фактический X пути в заданном Y (около 0.75 px). null — Y не на пути.
  double? _pathXAtY(Path path, double targetY, {double eps = 0.75}) {
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += 0.5) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        if ((t.position.dy - targetY).abs() < eps) return t.position.dx;
      }
    }
    return null;
  }

  String? _findYesMergeTarget(
    FlowchartGraph g,
    String logicName,
    Map<String, _MergeInfo> mergeInfoByTarget,
  ) {
    ConnectionData? yesConn, noConn;
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'yes') yesConn = c;
      if (c.sourcePort == 'no') noConn = c;
    }
    if (yesConn == null) return null;

    // Прямой случай: yes-таргет сам merge-точка
    if (mergeInfoByTarget.containsKey(yesConn.targetNodeName)) {
      return yesConn.targetNodeName;
    }
    if (noConn == null) return null;

    // 1) Всё, что достижимо из no-ветки
    final noReach = <String>{};
    final q1 = <String>[noConn.targetNodeName];
    while (q1.isNotEmpty) {
      final cur = q1.removeAt(0);
      if (!noReach.add(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        q1.add(c.targetNodeName);
      }
    }

    // 2) BFS от yes-ветки: первая merge-точка, достижимая и из no
    //    (т.е. реальная точка слияния веток этого логического блока)
    final yesVisited = <String>{};
    final q2 = <String>[yesConn.targetNodeName];
    while (q2.isNotEmpty) {
      final cur = q2.removeAt(0);
      if (!yesVisited.add(cur)) continue;
      if (noReach.contains(cur) && mergeInfoByTarget.containsKey(cur)) {
        debugPrint(
          '[findYesMerge] $logicName: yes=${yesConn.targetNodeName} '
          'no=${noConn.targetNodeName} -> merge=$cur',
        );
        return cur;
      }
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        q2.add(c.targetNodeName);
      }
    }

    debugPrint(
      '[findYesMerge] $logicName: yes=${yesConn.targetNodeName} '
      'no=${noConn.targetNodeName} -> merge=none',
    );
    return null;
  }

  ConnectionData? _findLastYesEdge(
    FlowchartGraph g,
    String logicName,
    String mergeName,
  ) {
    ConnectionData? yesConn;
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'yes') yesConn = c;
    }
    if (yesConn == null) return null;
    if (yesConn.targetNodeName == mergeName) return yesConn;

    String cur = yesConn.targetNodeName;
    final visited = <String>{logicName};
    ConnectionData? lastYesOut;

    while (visited.add(cur)) {
      ConnectionData? nextYes;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'yes' || c.sourcePort == 'out') {
          if (c.targetNodeName == mergeName) return c;
          nextYes ??= c;
        }
      }
      if (nextYes == null) return lastYesOut;
      lastYesOut = nextYes;
      cur = nextYes.targetNodeName;
    }
    return lastYesOut;
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

  // / Плюс на exit-ветке
  Offset? _exitPlusPosition(Path path, NodeModel src, FlowchartGraph g) {
    final srcCenterX = src.position.dx + router.nodeSize.width / 2;
    final srcBottom = src.position.dy + router.nodeSize.height;
    final segs = _extractSegments(path);
    if (segs.isEmpty) return null;

    final horzs = <_Seg>[];
    _Seg? deepest;
    for (final s in segs) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (isHorz) horzs.add(s);
      if (!isHorz) continue;
      if (deepest == null || s.start.dy > deepest.start.dy) {
        deepest = s;
      }
    }
    if (horzs.isEmpty) return null;
    // if (deepest == null) return null;
    //
    if (deepest == null || deepest.start.dy < srcBottom) {
      final branchBottom = _branchBottom(g, src.name);
      debugPrint(
        '[exit+ FALLBACK] src=${src.name} '
        'deepestY=${deepest?.start.dy.toStringAsFixed(1) ?? "null"} '
        'srcBottom=${srcBottom.toStringAsFixed(1)} '
        '→ placing at srcBottom+24',
      );
      return Offset(srcCenterX, branchBottom + 45);
    }

    final xLo = math.min(deepest.start.dx, deepest.end.dx);
    final xHi = math.max(deepest.start.dx, deepest.end.dx);
    final x = srcCenterX.clamp(xLo, xHi);

    debugPrint(
      '[exit+] src=${src.name} srcCenterX=$srcCenterX '
      'segments=${segs.length} '
      'deepestY=${deepest.start.dy.toStringAsFixed(1)} '
      'xRange=[${xLo.toStringAsFixed(1)},${xHi.toStringAsFixed(1)}] '
      'plusX=${x.toStringAsFixed(1)}',
    );

    return Offset(srcCenterX, deepest.start.dy);
  }

  double _branchBottom(FlowchartGraph g, String rootName) {
    final root = g.nodes[rootName];
    if (root == null) return 0;

    double maxBottom = root.position.dy + router.nodeSize.height;
    final visited = <String>{rootName};
    final queue = <String>[];

    for (final c in g.outgoing[rootName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'exit') continue;
      if (c.targetPort == 'loopback') continue;
      queue.add(c.targetNodeName);
    }

    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      final n = g.nodes[cur];
      if (n == null) continue;
      final b = n.position.dy + router.nodeSize.height;
      if (b > maxBottom) maxBottom = b;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return maxBottom;
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
