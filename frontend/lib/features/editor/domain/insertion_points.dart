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

    final loopbackMerges = <String, _LoopbackMergeInfo>{};
    for (final node in g.nodes.values) {
      if (node.data is! LogicBlock) continue;

      ConnectionData? yesConn, noConn;
      for (final c in g.outgoing[node.name] ?? const <ConnectionData>[]) {
        if (c.sourcePort == 'yes') yesConn = c;
        if (c.sourcePort == 'no') noConn = c;
      }
      if (yesConn == null || noConn == null) continue;

      final yes = _traverseToLoopback(g, yesConn);
      final no = _traverseToLoopback(g, noConn);
      if (yes.landings.isEmpty || no.landings.isEmpty) continue;

      final forName = yes.landings.first.targetNodeName;
      if (g.nodes[forName]?.data is! ForBlock) continue;
      if (!no.landings.any((c) => c.targetNodeName == forName)) continue;

      final shared = yes.intermediate.intersection(no.intermediate);
      if (shared.isNotEmpty) {
        debugPrint(
          '[logicLoopback+/skip] ${node.name}: branches already merged at '
          '${shared.take(3).join(",")} — no AfterMerge plus',
        );
        continue;
      }

      loopbackMerges[node.name] = _LoopbackMergeInfo(
        mainLanding: yes.landings.first,
        otherLandings: no.landings
            .where((c) => c.targetNodeName == forName)
            .toList(),
        forName: forName,
        logicName: node.name,
      );
    }
    // Все target с >= 2 входящими non-loopback
    final incomingByTarget = <String, List<ConnectionData>>{};
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      incomingByTarget.putIfAbsent(conn.targetNodeName, () => []).add(conn);
    }

    // Единый AfterMerge-плюс на yes→loopback для каждого логического merge
    for (final merge in loopbackMerges.values) {
      final pos = _loopbackAfterMergePosition(g, merge);
      if (pos == null) continue;

      final otherIds = merge.otherLandings
          .where((c) => c.id != null)
          .map((c) => c.id!)
          .toList();

      debugPrint(
        '[logicLoopback+/afterMerge] logic=${merge.logicName} '
        'for=${merge.forName} '
        'main=${merge.mainLanding.sourceNodeName}.'
        '${merge.mainLanding.sourcePort} '
        'x=${pos.dx.toStringAsFixed(1)} y=${pos.dy.toStringAsFixed(1)} '
        'others=${otherIds.length}',
      );

      points.add(
        AfterMergePoint(
          position: pos,
          connection: merge.mainLanding,
          mergeOtherConnIds: otherIds,
        ),
      );
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
      final isExitLoopback =
          conn.targetPort == 'loopback' && conn.sourcePort == 'exit';
      final isLogicBranchLoopback =
          conn.targetPort == 'loopback' &&
          (conn.sourcePort == 'yes' || conn.sourcePort == 'no') &&
          g.nodes[conn.targetNodeName]?.data is ForBlock;

      if (conn.targetPort == 'loopback' &&
          !isBodyLoopback &&
          !isExitLoopback &&
          !isLogicBranchLoopback) {
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
        if (plusPos != null) {
          points.add(ExitLoopbackPoint(position: plusPos, connection: conn));
        }
        continue;
      }

      if (isLogicBranchLoopback) {
        // final src = g.nodes[conn.sourceNodeName];
        // Offset? plusPos;

        final plusPos = _firstVerticalMidpoint(path) ?? _midOfPath(path);

        // if (conn.sourcePort == 'no') {
        //   plusPos = _firstVerticalMidpoint(path) ?? _midOfPath(path);
        // } else {
        //   plusPos = src != null
        //       ? _logicLoopbackPlusPosition(path, src)
        //       : (_firstVerticalMidpoint(path) ?? _midOfPath(path));
        // }
        if (plusPos != null) {
          debugPrint(
            '[logicLoopback+] ${conn.sourceNodeName}--${conn.sourcePort}->'
            '${conn.targetNodeName}.loopback: '
            'x=${plusPos.dx.toStringAsFixed(1)} '
            'y=${plusPos.dy.toStringAsFixed(1)}',
          );
          points.add(OnConnectionPoint(position: plusPos, connection: conn));
        }
        continue;
      }

      if (conn.sourcePort == 'yes') {
        final src = g.nodes[conn.sourceNodeName];
        if (src == null) continue;

        final offset = router.spacing.mergeGap * 2;
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
              (p) => p.connection.id == lastEdge.id,
            );
            if (!alreadyHas) {
              final lastPath = router.build(lastEdge, g).path;

              _Seg? horiz;
              for (final s in _extractSegments(lastPath)) {
                final isHorz =
                    (s.start.dy - s.end.dy).abs() < 0.5 &&
                    (s.start.dx - s.end.dx).abs() > 0.5;
                if (!isHorz) continue;
                if ((s.start.dy - mergeInfo.mergeY).abs() < 1.0) {
                  horiz = s;
                  break;
                }
              }
              // var lastX;
              Offset? plusPos;
              if (horiz != null) {
                final xLo = math.min(horiz.start.dx, horiz.end.dx);
                final xHi = math.max(horiz.start.dx, horiz.end.dx);
                plusPos = Offset(
                  xHi - router.spacing.plusInsetX,
                  horiz.start.dy,
                );
                debugPrint(
                  '[yesPlus/horizontal] ${conn.sourceNodeName}--yes->'
                  '${conn.targetNodeName}: '
                  'x=${plusPos.dx.toStringAsFixed(1)} '
                  'y=${plusPos.dy.toStringAsFixed(1)} '
                  'xRange=[${xLo.toStringAsFixed(1)},${xHi.toStringAsFixed(1)}]',
                );
              } else {
                final lastX = _pathXAtY(lastPath, targetY);
                if (lastX != null) {
                  plusPos = Offset(lastX, targetY);
                  debugPrint(
                    '[yesPlus/vertical] ${conn.sourceNodeName}--yes->'
                    '${conn.targetNodeName}: '
                    'x=${plusPos.dx.toStringAsFixed(1)} '
                    'y=${plusPos.dy.toStringAsFixed(1)}',
                  );
                } else {
                  debugPrint(
                    '[yesPlus/beforeMerge FAILED] ${conn.sourceNodeName}--yes->'
                    '${conn.targetNodeName}: lastX null '
                    'edge=${lastEdge.sourceNodeName}.${lastEdge.sourcePort} '
                    'targetY=${targetY.toStringAsFixed(1)}',
                  );
                }
              }
              if (plusPos != null) {
                final isOwnLastEdge =
                    lastEdge.sourceNodeName == conn.sourceNodeName &&
                    lastEdge.sourcePort == 'yes';

                if (isOwnLastEdge) {
                  final isDirect = lastEdge.targetNodeName == mergeNode;
                  if (isDirect) {
                    final startSamples = _samplePath(path);
                    if (startSamples.isNotEmpty) {
                      final s = startSamples.first;
                      plusPos = Offset(s.dx, s.dy + router.spacing.stepY / 4);
                    }
                  }

                  debugPrint(
                    '[yesPlus/beforeMerge] ${conn.sourceNodeName}--yes->'
                    '${conn.targetNodeName}: '
                    'x=${plusPos.dx.toStringAsFixed(1)} '
                    'y=${plusPos.dy.toStringAsFixed(1)} '
                    'direct=$isDirect lastEdge=${lastEdge.sourceNodeName}',
                  );
                  points.add(
                    OnConnectionPoint(position: plusPos, connection: lastEdge),
                  );
                  placed = true;
                }
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
            points.add(OnConnectionPoint(position: plusPos, connection: conn));
            // points.add(InsertionPoint(plusPos, conn));
            placed = true;
          } else {
            debugPrint(
              '[yesPlus/ownMidpoint FAILED] ${conn.sourceNodeName}--yes->'
              '${conn.targetNodeName}: midpoint null',
            );
          }
        }
        continue;
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
        if (plusPos != null) {
          points.add(OnConnectionPoint(position: plusPos, connection: conn));
        }
        continue;
      } else if (conn.targetPort == 'loopback') {
        _Seg? horiz;
        for (final s in _extractSegments(path)) {
          final isHorz =
              (s.start.dy - s.end.dy).abs() < 0.5 &&
              (s.start.dx - s.end.dx).abs() > 0.5;
          if (isHorz) {
            horiz = s;
            break;
          }
        }
        if (horiz != null) {
          final xLo = math.min(horiz.start.dx, horiz.end.dx);
          final xHi = math.max(horiz.start.dx, horiz.end.dx);
          plusPos = Offset(xHi, horiz.start.dy - 10);
          debugPrint(
            '[outPlus/loopback] ${conn.sourceNodeName}--${conn.sourcePort}->'
            '${conn.targetNodeName}.loopback: '
            'x=${plusPos.dx.toStringAsFixed(1)} '
            'y=${plusPos.dy.toStringAsFixed(1)} '
            'xRange=[${xLo.toStringAsFixed(1)},${xHi.toStringAsFixed(1)}]',
          );
        } else {
          plusPos = _firstVerticalMidpoint(path) ?? _midOfPath(path);
        }
      } else {
        final samples = _samplePath(path);
        if (samples.isNotEmpty) {
          final start = samples.first;
          plusPos = Offset(start.dx, start.dy + router.spacing.stepY / 4 - 15);
        } else {
          plusPos = _firstVerticalMidpoint(path) ?? _midOfPath(path);
        }
      }
      if (plusPos != null) {
        points.add(OnConnectionPoint(position: plusPos, connection: conn));
      }
    }

    for (final entry in mergeInfoByTarget.entries) {
      final targetName = entry.key;
      final info = entry.value;

      final sourceGroups = <String, List<ConnectionData>>{};
      for (final c in info.incoming) {
        sourceGroups.putIfAbsent(c.sourceNodeName, () => []).add(c);
      }

      final trivialSources = sourceGroups.entries
          .where((e) => e.value.length >= 2)
          .toList();

      if (trivialSources.isEmpty) {
        final afterY = (info.maxLandingY + info.targetTop) / 2;
        final otherIds = info.incoming
            .where((c) => c.id != null && c.id != info.deepestEdge.id)
            .map((c) => c.id!)
            .toList();
        debugPrint(
          '[afterPlus/merge] target=$targetName '
          'x=${info.centerX.toStringAsFixed(1)} '
          'y=${afterY.toStringAsFixed(1)} '
          'others=${otherIds.length}',
        );
        points.add(
          AfterMergePoint(
            position: Offset(info.centerX, afterY),
            connection: info.deepestEdge,
            mergeOtherConnIds: otherIds,
          ),
        );
        // }
      } else {
        for (final sg in trivialSources) {
          final landingYs = <double>[];
          for (final c in sg.value) {
            final path = router.build(c, g).path;
            final y = _landingYAt(path, info.centerX, info.targetTop);
            if (y != null) landingYs.add(y);
          }
          if (landingYs.isEmpty) continue;
          landingYs.sort();

          // Реальная точка слияния — где последняя ветка коснулась общей вертикали
          final trueMergeY = landingYs.last;

          // Ближайшее «событие» ниже: верх первого блока на X=centerX,
          // который не является targetName. Если такого нет — сам targetTop.
          double nextEventY = info.targetTop;
          for (final e in g.nodes.entries) {
            if (e.key == targetName) continue;
            final n = e.value;
            if (n.position.dx + router.nodeSize.width < info.centerX) continue;
            if (n.position.dx > info.centerX) continue;
            if (n.position.dy <= trueMergeY + 0.5) continue;
            if (n.position.dy >= info.targetTop - 0.5) continue;
            if (n.position.dy < nextEventY) nextEventY = n.position.dy;
          }

          // final afterY = (trueMergeY + nextEventY) / 2;
          //
          final afterY = math.min((trueMergeY + nextEventY) / 2, trueMergeY);

          final srcNode = g.nodes[sg.key];
          final srcCenterX = srcNode == null
              ? info.centerX
              : srcNode.position.dx + router.nodeSize.width / 2;

          final isShifted = (srcCenterX - info.centerX).abs() > 0.5;
          final x = isShifted ? srcCenterX - 15 : srcCenterX;

          final otherIds = sg.value
              .where((c) => c.id != null && c.id != sg.value.first.id)
              .map((c) => c.id!)
              .toList();

          debugPrint(
            '[afterPlus/source] target=$targetName source=${sg.key} '
            'trueMergeY=${trueMergeY.toStringAsFixed(1)} '
            'nextEventY=${nextEventY.toStringAsFixed(1)} '
            'x=${x.toStringAsFixed(1)} y=${afterY.toStringAsFixed(1)} '
            'shifted=$isShifted others=${otherIds.length}',
          );
          points.add(
            AfterMergePoint(
              position: Offset(x, afterY),
              connection: sg.value.first,
              mergeOtherConnIds: otherIds,
            ),
          );
        }

        // Если к target идут и другие источники, кроме trivial-мерджей,
        // нужен ещё один плюс — «после слияния всех веток» у самого target.
        if (sourceGroups.length > trivialSources.length) {
          final afterY = (info.maxLandingY + info.targetTop) / 2;
          final otherIds = info.incoming
              .where((c) => c.id != null && c.id != info.deepestEdge.id)
              .map((c) => c.id!)
              .toList();
          debugPrint(
            '[afterPlus/merge] target=$targetName '
            'x=${info.centerX.toStringAsFixed(1)} '
            'y=${afterY.toStringAsFixed(1)} others=${otherIds.length}',
          );
          points.add(
            AfterMergePoint(
              position: Offset(info.centerX, afterY),
              connection: info.deepestEdge,
              mergeOtherConnIds: otherIds,
            ),
          );
        }
      }
    }

    return points;
  }

  /// Обходит ветку транзитивно до всех приземлений на loopback.
  /// Возвращает landings (рёбра с targetPort == 'loopback') и
  /// intermediate — множество промежуточных узлов (без целевого For).
  _LoopbackTraversal _traverseToLoopback(
    FlowchartGraph g,
    ConnectionData start,
  ) {
    if (start.targetPort == 'loopback') {
      return _LoopbackTraversal(landings: [start], intermediate: const {});
    }
    final landings = <ConnectionData>[];
    final intermediate = <String>{};
    final visited = <String>{};
    final queue = <String>[start.targetNodeName];

    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      intermediate.add(cur);
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') {
          landings.add(c);
          continue;
        }
        queue.add(c.targetNodeName);
      }
    }
    return _LoopbackTraversal(landings: landings, intermediate: intermediate);
  }

  /// Середина самой длинной горизонтали yes→loopback пути.
  /// Это тот участок, где после слияния с no обе ветки идут уже вместе,
  /// и куда логично ставить AfterMerge-плюс.
  Offset? _loopbackAfterMergePosition(
    FlowchartGraph g,
    _LoopbackMergeInfo merge,
  ) {
    final yesPath = router.build(merge.mainLanding, g).path;
    if (yesPath.computeMetrics().isEmpty) return null;

    _Seg? longest;
    double longestLen = 0;
    for (final s in _extractSegments(yesPath)) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (!isHorz) continue;
      final len = (s.end.dx - s.start.dx).abs();
      if (len > longestLen) {
        longestLen = len;
        longest = s;
      }
    }
    if (longest == null) return _midOfPath(yesPath);

    return Offset((longest.start.dx + longest.end.dx) / 2, longest.start.dy);
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
        if (c.sourcePort == 'yes' ||
            c.sourcePort == 'out' ||
            c.sourcePort == 'exit') {
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

class _LoopbackMergeInfo {
  final ConnectionData mainLanding;
  final List<ConnectionData> otherLandings;
  final String forName;
  final String logicName;
  const _LoopbackMergeInfo({
    required this.mainLanding,
    required this.otherLandings,
    required this.forName,
    required this.logicName,
  });
}

class _LoopbackTraversal {
  final List<ConnectionData> landings;
  final Set<String> intermediate;
  const _LoopbackTraversal({
    required this.landings,
    required this.intermediate,
  });
}
