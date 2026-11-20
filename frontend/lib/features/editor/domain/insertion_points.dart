import 'dart:math' as math;
import 'package:flowchart_editor_frontend/features/editor/domain/graph_geometry.dart';
import 'package:flowchart_editor_frontend/features/editor/domain/path_geometry.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../factories/node_factory.dart';
import '../models/flow_models.dart';
import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';

class InsertionPointsService {
  final ConnectionRouter router;
  const InsertionPointsService({required this.router});

  /// Все рёбра из поддерева [noConn] (не считая loopback), которые приходят
  /// в [targetName]. Если [noConn] сам идёт прямо в target — вернётся только он.
  Set<ConnectionData> _subtreeExitsToTarget(
    FlowchartGraph g,
    ConnectionData noConn,
    String targetName,
  ) {
    final result = <ConnectionData>{};
    if (noConn.targetNodeName == targetName) {
      result.add(noConn);
      return result;
    }
    final visited = <String>{};
    final queue = <String>[noConn.targetNodeName];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.targetNodeName == targetName) {
          result.add(c);
        } else {
          queue.add(c.targetNodeName);
        }
      }
    }
    return result;
  }

  List<InsertionPoint> compute(FlowchartGraph g) {
    final points = <InsertionPoint>[];

    debugPrint(
      '[compute] enter nodes=${g.nodes.length} conns=${g.connections.length}',
    );

    // Кеш всех путей — один раз на compute(), используем в нескольких
    // ветках (yes/no/out/loopback) как obstacles для firstVerticalMidpoint.
    final allPaths = <String, Path>{};
    for (final c in g.connections) {
      final id = c.id;
      if (id == null) continue;
      final p = router.build(c, g).path;
      if (p.computeMetrics().isNotEmpty) allPaths[id] = p;
    }

    List<Path> otherPaths(ConnectionData self) => allPaths.entries
        .where((e) => e.key != self.id)
        .map((e) => e.value)
        .toList(growable: false);

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
            : (PathGeometry.firstVerticalMidpoint(path) ??
                  PathGeometry.midpoint(path));
        if (plusPos != null) {
          points.add(ExitLoopbackPoint(position: plusPos, connection: conn));
        }
        continue;
      }

      if (isLogicBranchLoopback) {
        final plusPos =
            PathGeometry.firstVerticalMidpoint(
              path,
              obstacles: otherPaths(conn),
            ) ??
            PathGeometry.midpoint(path);
        if (plusPos != null) {
          points.add(OnConnectionPoint(position: plusPos, connection: conn));
        }
        continue;
      }

      if (conn.sourcePort == 'yes') {
        final plusPos =
            PathGeometry.firstVerticalMidpoint(
              path,
              obstacles: otherPaths(conn),
            ) ??
            PathGeometry.midpoint(path);
        if (plusPos != null) {
          points.add(OnConnectionPoint(position: plusPos, connection: conn));
        }
        continue;
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = PathGeometry.firstVerticalMidpoint(
          path,
          obstacles: otherPaths(conn),
        );
        // plusPos = PathGeometry.firstVerticalMidpoint(path);
        if (plusPos != null) {
          points.add(OnConnectionPoint(position: plusPos, connection: conn));
        }
        continue;
      } else if (conn.targetPort == 'loopback') {
        PathSegment? horiz;
        for (final s in PathGeometry.segments(path)) {
          final isHorz =
              (s.start.dy - s.end.dy).abs() < 0.5 &&
              (s.start.dx - s.end.dx).abs() > 0.5;
          if (isHorz) {
            horiz = s;
            break;
          }
        }
        if (horiz != null) {
          // final xLo = math.min(horiz.start.dx, horiz.end.dx);
          final xHi = math.max(horiz.start.dx, horiz.end.dx);
          plusPos = Offset(xHi, horiz.start.dy - 10);
        } else {
          plusPos =
              PathGeometry.firstVerticalMidpoint(path) ??
              PathGeometry.midpoint(path);
        }
      } else {
        final samples = _samplePath(path);
        if (samples.isNotEmpty) {
          final start = samples.first;
          plusPos = Offset(start.dx, start.dy + router.spacing.stepY / 4 - 15);
        } else {
          plusPos =
              PathGeometry.firstVerticalMidpoint(path) ??
              PathGeometry.midpoint(path);
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

      // ───── Per-source aftermerge (Type A: другая колонка; Type C: та же) ─────
      for (final sg in sourceGroups.entries) {
        final srcNode = g.nodes[sg.key];
        if (srcNode == null || srcNode.data is! LogicBlock) continue;

        ConnectionData? mainConn;
        final otherIds = <String>[];

        if (sg.value.length >= 2) {
          // Тривиальная пара: несколько прямых рёбер из src в target (yes+no).
          mainConn =
              sg.value.firstWhereOrNull(
                (c) => c.sourcePort == 'yes' || c.sourcePort == 'out',
              ) ??
              sg.value.first;
          for (final c in sg.value) {
            if (c.id != null && c.id != mainConn.id) otherIds.add(c.id!);
          }
        } else {
          // Один прямой вход в target (yes/out). Если no-поддерево тоже
          // достигает target — сливаем yes с выходами поддерева.
          final only = sg.value.first;
          if (only.sourcePort != 'yes' && only.sourcePort != 'out') continue;
          final noConn = (g.outgoing[sg.key] ?? const <ConnectionData>[])
              .firstWhereOrNull((c) => c.sourcePort == 'no');
          if (noConn == null) continue;
          final exits = _subtreeExitsToTarget(g, noConn, targetName);
          if (exits.isEmpty) continue;
          mainConn = only;
          for (final c in exits) {
            if (c.id != null) otherIds.add(c.id!);
          }
        }

        // // main: yes/out если есть, иначе первая связь (в т.ч. --no для no-only)
        // final mainConn =
        //     sg.value.firstWhereOrNull(
        //       (c) => c.sourcePort == 'yes' || c.sourcePort == 'out',
        //     ) ??
        //     sg.value.first;

        // final otherIds = sg.value
        //     .where((c) => c.id != null && c.id != mainConn.id)
        //     .map((c) => c.id!)
        //     .toList();

        // otherIds: все ветки того же источника в этот target (trivial-пара)
        // // + joining-связь и её sibling (настоящий aftermerge)
        // final otherIds = <String>[];
        // for (final c in sg.value) {
        //   if (c.id != null && !identical(c, mainConn)) otherIds.add(c.id!);
        // }
        // final events = router.debugMergeEventsFor(g, mainConn);
        // if (events.isNotEmpty) {
        //   final joining = events.first.joiningConn;
        //   if (joining.id != null && !otherIds.contains(joining.id)) {
        //     otherIds.add(joining.id!);
        //   }
        //   // Если joining — часть тривиальной пары (yes+no одного источника
        //   // // в тот же target), тянем и sibling, иначе разорвём пару.
        //   // for (final sib in (g.outgoing[joining.sourceNodeName] ?? const [])) {
        //   //   if (sib.id == null || sib.id == joining.id) continue;
        //   //   if (sib.targetNodeName != joining.targetNodeName) continue;
        //   //   if (!otherIds.contains(sib.id)) otherIds.add(sib.id!);
        //   // }
        // }

        final srcBottom = srcNode.position.dy + router.nodeSize.height;
        final srcCenterX = srcNode.position.dx + router.nodeSize.width / 2;
        final busY = info.maxLandingY;
        if (busY <= 0 || srcBottom >= busY - 0.5) continue;

        final sameColumn = (srcCenterX - info.centerX).abs() < 0.5;
        final flowLeft = info.centerX < srcCenterX;

        final Offset plusPos;
        if (sameColumn) {
          // Type C: между блоком и его шиной, в общей колонке.
          // // Type C: центр между блоком и следующим блоком в той же колонке
          // (или busY, если следующего нет). Это чинит случай с вложенными
          // логическими блоками: плюс встаёт СРАЗУ после блока, не проваливаясь
          // в следующий.
          double nextBlockTop = busY;
          for (final e in g.nodes.entries) {
            if (e.key == sg.key) continue;
            final n = e.value;
            if ((n.position.dx - srcNode.position.dx).abs() > 0.5) continue;
            if (n.position.dy <= srcNode.position.dy + 1.0) continue;
            if (n.position.dy >= busY - 0.5) continue;
            if (n.position.dy < nextBlockTop) nextBlockTop = n.position.dy;
          }
          final y = (srcBottom + nextBlockTop) / 2;
          if (y <= srcBottom + 0.5 || y >= busY - 0.5) continue;
          plusPos = Offset(srcCenterX, y);
          // plusPos = Offset(srcCenterX, 20* (srcBottom + busY) / 2);
        } else {
          // Type A: на шине, в колонке источника.
          plusPos = Offset(
            flowLeft
                ? srcCenterX - router.spacing.arrowInset
                : srcCenterX + router.spacing.arrowInset,
            busY,
          );
        }

        debugPrint(
          '[afterPlus/source] target=$targetName source=${sg.key} '
          'type=${sameColumn ? "C" : "A"} '
          'x=${plusPos.dx.toStringAsFixed(1)} y=${plusPos.dy.toStringAsFixed(1)} '
          'others=${otherIds.length}',
        );
        points.add(
          AfterMergePoint(
            position: plusPos,
            connection: mainConn,
            mergeOtherConnIds: otherIds,
          ),
        );
      }

      //   // otherIds: другие ветки того же источника (trivial rejoin) +
      //   // ветки других источников, попадающие в ту же точку шины (same dropX).
      //   final mainDropX = router.debugDropX(g, mainConn);
      //   final otherIds = <String>[];
      //   for (final other in info.incoming) {
      //     if (other.id == null || identical(other, mainConn)) continue;
      //     if (other.sourceNodeName == sg.key) {
      //       otherIds.add(other.id!);
      //       continue;
      //     }
      //     final otherDropX = router.debugDropX(g, other);
      //     if ((otherDropX - mainDropX).abs() < 0.5) otherIds.add(other.id!);
      //   }

      //   debugPrint(
      //     '[afterPlus/source] target=$targetName source=${sg.key} '
      //     'type=${sameColumn ? "C" : "A"} '
      //     'x=${plusPos.dx.toStringAsFixed(1)} y=${plusPos.dy.toStringAsFixed(1)} '
      //     'others=${otherIds.length}',
      //   );
      //   points.add(
      //     AfterMergePoint(
      //       position: plusPos,
      //       connection: mainConn,
      //       mergeOtherConnIds: otherIds,
      //     ),
      //   );
      // }

      // ───── After-all (Type B): один на target ─────
      if (info.incoming.length >= 2) {
        final afterY = (info.maxLandingY + info.targetTop) / 2;
        final otherIds = info.incoming
            .where((c) => c.id != null && c.id != info.deepestEdge.id)
            .map((c) => c.id!)
            .toList();
        debugPrint(
          '[afterPlus/all] target=$targetName x=${info.centerX.toStringAsFixed(1)} '
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

      // final trivialSources = sourceGroups.entries
      //     .where((e) => e.value.length >= 2)
      //     .toList();

      // final hasNonTrivial = sourceGroups.length > trivialSources.length;

      // for (final sg in trivialSources) {
      //   final srcNode = g.nodes[sg.key];
      //   if (srcNode == null) continue;
      //   final srcBottom = srcNode.position.dy + router.nodeSize.height;
      //   final srcCenterX = srcNode.position.dx + router.nodeSize.width / 2;
      //   final busY = info.maxLandingY;
      //   if (srcBottom >= busY - 0.5) continue; // нет просвета блок→шина
      //   final y = (srcBottom + busY) / 2;
      //   final otherIds = sg.value
      //       .where((c) => c.id != null && c.id != sg.value.first.id)
      //       .map((c) => c.id!)
      //       .toList();

      //   if ((srcCenterX - info.centerX).abs() < 0.5) continue;

      //   // Справа-налево, если target левее источника.
      //   final flowLeft = info.centerX < srcCenterX;
      //   final plusX = flowLeft
      //       ? srcCenterX - router.spacing.arrowInset
      //       : srcCenterX + router.spacing.arrowInset;
      //   debugPrint(
      //     '[afterPlus/source] target=$targetName source=${sg.key} '
      //     'flowLeft=$flowLeft x=${plusX.toStringAsFixed(1)} '
      //     'y=${busY.toStringAsFixed(1)} others=${otherIds.length}',
      //   );
      //   points.add(
      //     AfterMergePoint(
      //       position: Offset(plusX, busY),
      //       connection: sg.value.first,
      //       mergeOtherConnIds: otherIds,
      //     ),
      //   );
      // }

      // Обрабатываем и нетривиальные источники: LogicBlock, у которого есть
      // хотя бы одна yes/out-связь в этот target (right-to-left). Даёт плюс
      // «после блока в колонке» для случаев вроде col 3 (1ae07a98: yes→target,
      // no→другой узел — не пара, но ветка в target идёт).
      // final handledCenters = <double>{
      //   for (final sg in trivialSources)
      //     if (g.nodes[sg.key] != null)
      //       g.nodes[sg.key]!.position.dx + router.nodeSize.width / 2,
      // };

      // for (final sg in sourceGroups.entries) {
      //   if (trivialSources.any((t) => t.key == sg.key)) continue;
      //   final srcNode = g.nodes[sg.key];
      //   if (srcNode == null || srcNode.data is! LogicBlock) continue;

      //   final srcCenterX = srcNode.position.dx + router.nodeSize.width / 2;
      //   if (handledCenters.contains(srcCenterX)) continue;

      //   final hasYesOrOutToTarget = sg.value.any(
      //     (c) => c.sourcePort == 'yes' || c.sourcePort == 'out',
      //   );
      //   if (!hasYesOrOutToTarget) continue;

      //   final busY = info.maxLandingY;
      //   if (busY <= 0) continue;
      //   final srcBottom = srcNode.position.dy + router.nodeSize.height;
      //   if (srcBottom >= busY - 0.5) continue;

      //   final events = router.debugMergeEventsFor(g, sg.value.first);

      //   // .        // Плюс — под логическим блоком, на уровне шины.
      //   //         final plusX = srcCenterX;

      //   //         // Семантика «after merge»: помимо нашей ветки, тянем в новый блок
      //   //         // и ту ветку, что создаёт слияние. Новый блок окажется в колонке
      //   //         // источника (через yes-путь), но будет принимать оба потока.
      //   //         final otherIds = <String>[];
      //   //         if (events.isNotEmpty && events.first.joiningConn.id != null) {
      //   //           otherIds.add(events.first.joiningConn.id!);
      //   //         }

      //   //         debugPrint(
      //   //           '[afterPlus/nontrivial] target=$targetName source=${sg.key} '
      //   //           'x=${plusX.toStringAsFixed(1)} y=${busY.toStringAsFixed(1)} '
      //   //           'xMerge=${events.isNotEmpty ? events.first.xMerge.toStringAsFixed(1) : "none"} '
      //   //           'others=${otherIds.length}',
      //   //         );
      //   //         points.add(
      //   //           AfterMergePoint(
      //   //             position: Offset(plusX, busY),
      //   //             connection: sg.value.first,
      //   //             mergeOtherConnIds: otherIds,
      //   //           ),
      //   //         );

      //   final y = (srcBottom + busY) / 2;
      //   debugPrint(
      //     '[afterPlus/source-nontrivial] target=$targetName '
      //     'source=${sg.key} x=${srcCenterX.toStringAsFixed(1)} '
      //     'y=${y.toStringAsFixed(1)}',
      //   );
      //   points.add(
      //     OnConnectionPoint(
      //       position: Offset(srcCenterX, y),
      //       connection: sg.value.first,
      //     ),
      //   );

      //   // final flowLeft = info.centerX < srcCenterX;
      //   // final plusX = flowLeft
      //   //     ? srcCenterX - router.spacing.arrowInset
      //   //     : srcCenterX + router.spacing.arrowInset;

      //   // debugPrint(
      //   //   '[afterPlus/nontrivial] target=$targetName source=${sg.key} '
      //   //   'flowLeft=$flowLeft x=${plusX.toStringAsFixed(1)} '
      //   //   'y=${busY.toStringAsFixed(1)}',
      //   // );
      //   // // OnConnectionPoint, а не AfterMergePoint: семантически это
      //   // // «плюс на ветке после блока», а не «после слияния ветвей».
      //   // points.add(
      //   //   OnConnectionPoint(
      //   //     position: Offset(plusX, busY),
      //   //     connection: sg.value.first,
      //   //   ),
      //   // );

      //   // debugPrint(
      //   //   '[afterPlus/source-nontrivial] target=$targetName '
      //   //   'source=${sg.key} flowLeft=$flowLeft x=${plusX.toStringAsFixed(1)} '
      //   //   'y=${busY.toStringAsFixed(1)}',
      //   // );
      //   // points.add(
      //   //   AfterMergePoint(
      //   //     position: Offset(plusX, busY),
      //   //     connection: sg.value.first,
      //   //     // mergeOtherConnIds: const [],
      //   //   ),
      //   // );

      //   // final noConn = (g.outgoing[sg.key] ?? const <ConnectionData>[])
      //   //     .firstWhereOrNull((c) => c.sourcePort == 'no');
      //   // points.add(
      //   //   AfterMergePoint(
      //   //     position: Offset(srcCenterX, y),
      //   //     connection: sg.value.first,
      //   //     mergeOtherConnIds: noConn?.id != null ? [noConn!.id!] : const [],
      //   //   ),
      //   // );
      //   // points.add(
      //   //   AfterMergePoint(
      //   //     position: Offset(srcCenterX, y),
      //   //     connection: sg.value.first,
      //   //     mergeOtherConnIds:
      //   //         const [], // other ветки этого источника в другой target
      //   //   ),
      //   // );
      // }

      // if (trivialSources.isEmpty || hasNonTrivial) {
      //   final afterY = (info.maxLandingY + info.targetTop) / 2;
      //   final otherIds = info.incoming
      //       .where((c) => c.id != null && c.id != info.deepestEdge.id)
      //       .map((c) => c.id!)
      //       .toList();
      //   points.add(
      //     AfterMergePoint(
      //       position: Offset(info.centerX, afterY),
      //       connection: info.deepestEdge,
      //       mergeOtherConnIds: otherIds,
      //     ),
      //   );
      //   // }
      // } else {
      //   for (final sg in trivialSources) {
      //     final landingYs = <double>[];
      //     for (final c in sg.value) {
      //       final path = router.build(c, g).path;
      //       final y = PathGeometry.landingYAt(
      //         path,
      //         info.centerX,
      //         info.targetTop,
      //       );
      //       if (y != null) landingYs.add(y);
      //     }
      //     if (landingYs.isEmpty) continue;
      //     landingYs.sort();

      //     // Реальная точка слияния — где последняя ветка коснулась общей вертикали
      //     final trueMergeY = landingYs.last;

      //     // Ближайшее «событие» ниже: верх первого блока на X=centerX,
      //     // который не является targetName. Если такого нет — сам targetTop.
      //     double nextEventY = info.targetTop;
      //     for (final e in g.nodes.entries) {
      //       if (e.key == targetName) continue;
      //       final n = e.value;
      //       if (n.position.dx + router.nodeSize.width < info.centerX) continue;
      //       if (n.position.dx > info.centerX) continue;
      //       if (n.position.dy <= trueMergeY + 0.5) continue;
      //       if (n.position.dy >= info.targetTop - 0.5) continue;
      //       if (n.position.dy < nextEventY) nextEventY = n.position.dy;
      //     }

      //     // final afterY = (trueMergeY + nextEventY) / 2;
      //     //
      //     var afterY = math.min((trueMergeY + nextEventY) / 2, trueMergeY);

      //     final srcNode = g.nodes[sg.key];
      //     final srcCenterX = srcNode == null
      //         ? info.centerX
      //         : srcNode.position.dx + router.nodeSize.width / 2;

      //     final isShifted = (srcCenterX - info.centerX).abs() > 0.5;
      //     final x = isShifted ? srcCenterX - 15 : srcCenterX;

      //     final otherIds = sg.value
      //         .where((c) => c.id != null && c.id != sg.value.first.id)
      //         .map((c) => c.id!)
      //         .toList();

      //     debugPrint(
      //       '[afterPlus/source] target=$targetName source=${sg.key} '
      //       'trueMergeY=${trueMergeY.toStringAsFixed(1)} '
      //       'nextEventY=${nextEventY.toStringAsFixed(1)} '
      //       'x=${x.toStringAsFixed(1)} y=${afterY.toStringAsFixed(1)} '
      //       'shifted=$isShifted others=${otherIds.length}',
      //     );

      //     points.add(
      //       AfterMergePoint(
      //         position: Offset(x, afterY),
      //         connection: sg.value.first,
      //         mergeOtherConnIds: otherIds,
      //       ),
      //     );
      //   }
      // }
    }

    return points;
  }

  // ──────────────────────────── merge-info ────────────────────────────

  /// Информация о merge-точке.
  ///
  /// `busY` — единая высота горизонтали для всех не-exit, не-loopback
  /// связей в этот target (см. `ConnectionRouter._busY`). `deepestEdge` —
  /// связь с самым длинным горизонтальным плечом: она «внешняя», к ней
  /// привязывается `AfterMergePoint` как к main.
  _MergeInfo? _computeMergeInfo(
    FlowchartGraph g,
    List<ConnectionData> incoming,
    NodeModel target,
  ) {
    final centerX = target.position.dx + router.nodeSize.width / 2;
    final targetTop = target.position.dy;

    // Единый источник «где шина». Если её нет (все связи вертикальные,
    // или нет горизонталей) — merge-точки нет.
    final busY = router.debugBusY(g, target.name);
    if (busY <= 0) {
      // debugPrint('[merge] target=${target.name}: NO MERGE (no horizontal bus)');
      return null;
    }

    ConnectionData? deepestEdge;
    double deepestDist = 0;
    for (final c in incoming) {
      if (c.sourcePort == 'exit') continue;
      if (c.targetPort == 'loopback') continue;
      final dropX = router.debugDropX(g, c);
      final dist = (dropX - centerX).abs();
      if (deepestEdge == null || dist > deepestDist) {
        deepestDist = dist;
        deepestEdge = c;
      }
    }
    if (deepestEdge == null) {
      // debugPrint('[merge] target=${target.name}: NO MERGE (no edge)');
      return null;
    }

    final gap = targetTop - busY;
    // debugPrint(
    //   '[merge] target=${target.name} '
    //   'busY=${busY.toStringAsFixed(1)} targetTop=$targetTop '
    //   'gap=${gap.toStringAsFixed(1)} '
    //   'inputs=${incoming.length} '
    //   'deepest=${deepestEdge.sourceNodeName}.${deepestEdge.sourcePort}',
    // );

    if (gap < 5) {
      // debugPrint('[merge] target=${target.name}: NO MERGE (gap < 5)');
      return null;
    }

    return _MergeInfo(
      incoming: incoming,
      deepestEdge: deepestEdge,
      busY: busY,
      targetTop: targetTop,
      centerX: centerX,
    );
  }

  // ──────────────────────────── loopback / exit ────────────────────────────

  Offset? _loopbackAfterMergePosition(
    FlowchartGraph g,
    _LoopbackMergeInfo merge,
  ) {
    final yesPath = router.build(merge.mainLanding, g).path;
    if (yesPath.computeMetrics().isEmpty) return null;

    final longest = PathGeometry.longestHorizontal(yesPath);
    if (longest == null) return PathGeometry.midpoint(yesPath);

    return Offset((longest.start.dx + longest.end.dx) / 2, longest.start.dy);
  }

  Offset? _exitPlusPosition(Path path, NodeModel src, FlowchartGraph g) {
    final srcCenterX = src.position.dx + router.nodeSize.width / 2;
    final srcBottom = src.position.dy + router.nodeSize.height;
    final segs = PathGeometry.segments(path);
    if (segs.isEmpty) return null;

    PathSegment? deepest;
    for (final s in segs) {
      if (!s.isHorizontal) continue;
      if (deepest == null || s.start.dy > deepest.start.dy) {
        deepest = s;
      }
    }
    if (deepest == null || deepest.start.dy < srcBottom) {
      final branchBottom = src.data is ForBlock
          ? GraphGeometry.bodySubtreeBottom(g, src.name, router.nodeSize)
          : GraphGeometry.logicBranchBottom(g, src.name, router.nodeSize);
      // debugPrint(
      //   '[exit+ FALLBACK] src=${src.name} '
      //   'deepestY=${deepest?.start.dy.toStringAsFixed(1) ?? "null"} '
      //   'srcBottom=${srcBottom.toStringAsFixed(1)} '
      //   '→ placing at branchBottom+45',
      // );
      return Offset(srcCenterX, branchBottom + 45);
    }

    // final xLo = math.min(deepest.start.dx, deepest.end.dx);
    // final xHi = math.max(deepest.start.dx, deepest.end.dx);

    // debugPrint(
    //   '[exit+] src=${src.name} srcCenterX=$srcCenterX '
    //   'segments=${segs.length} '
    //   'deepestY=${deepest.start.dy.toStringAsFixed(1)} '
    //   'xRange=[${xLo.toStringAsFixed(1)},${xHi.toStringAsFixed(1)}] '
    //   'plusX=${srcCenterX.toStringAsFixed(1)}',
    // );

    return Offset(srcCenterX, deepest.start.dy);
  }

  // ──────────────────────────── BFS / цепочки (без изменений) ────────────────────────────

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
}

class _MergeInfo {
  final List<ConnectionData> incoming;
  final ConnectionData deepestEdge;
  final double busY;
  final double targetTop;
  final double centerX;

  /// Backward-compat: раньше это было «самое низкое landing Y», теперь
  /// это общая шина (== `busY`).
  double get maxLandingY => busY;
  double get mergeY => busY;

  const _MergeInfo({
    required this.incoming,
    required this.deepestEdge,
    required this.busY,
    required this.targetTop,
    required this.centerX,
  });
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
