import 'package:collection/collection.dart';
import 'package:flowchart_editor_frontend/features/editor/domain/merge_detector.dart';
import 'package:flutter/material.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import 'flowchart_graph.dart';
import 'layout_engine.dart';
import 'dart:math' as math;
import 'dart:core';
import '../models/flow_models.dart';
import 'graph_geometry.dart';

class ArrowMarker {
  final Offset position;
  final double angle;
  const ArrowMarker(this.position, this.angle);
}

class RoutedConnection {
  final Path path;
  final List<ArrowMarker> arrows;
  const RoutedConnection(this.path, [this.arrows = const []]);
}

class ConnectionRouter {
  final Size nodeSize;
  final LayoutSpacing spacing;

  ConnectionRouter({required this.nodeSize, required this.spacing});

  FlowchartGraph? _busYCacheGraph;
  final Map<String, double> _busYCache = {};

  void _ensureCaches(FlowchartGraph g) {
    if (!identical(_busYCacheGraph, g)) {
      _busYCache.clear();
      _busYCacheGraph = g;
    }
  }

  late final MergeDetector _mergeDetector = MergeDetector(router: this);

  void resetCache() {
    _busYCache.clear();
    _busYCacheGraph = null;
    _mergeDetector.resetCache();
  }

  @visibleForTesting
  double debugBusY(FlowchartGraph g, String targetName) => _busY(g, targetName);

  @visibleForTesting
  double debugDropX(FlowchartGraph g, ConnectionData c) {
    final src = g.nodes[c.sourceNodeName];
    if (src == null) return 0;
    return _dropXOf(g, c, src);
  }

  @visibleForTesting
  List<MergeEvent> debugMergeEventsFor(FlowchartGraph g, ConnectionData c) =>
      _mergeDetector.forConnection(g, c);

  RoutedConnection build(ConnectionData conn, FlowchartGraph g) {
    _ensureCaches(g);
    final source = g.nodes[conn.sourceNodeName];
    final target = g.nodes[conn.targetNodeName];
    if (source == null || target == null) return RoutedConnection(Path());

    final start = _portPosition(source, conn.sourcePort, outgoing: true);
    final end = _portPosition(target, conn.targetPort, outgoing: false);

    if (conn.targetPort == 'loopback') {
      return _routeLoopback(start, end, g, conn);
    }

    return switch (conn.sourcePort) {
      'no' => _routeNo(start, end, g, conn),
      'exit' => _routeExit(start, end, g, conn),
      _ => _routeDefault(start, end, g, conn),
    };
  }

  /// Y общей горизонтальной шины перед [targetName].
  ///
  /// Все не-loopback, не-exit связи, приходящие в `in`-порт [targetName],
  /// используют одно и то же значение — иначе горизонтали не сливаются.
  ///
  /// Y = max по всем таким связям от:
  ///   - низа источника,
  ///   - низа нод-препятствий в X-диапазоне горизонтали связи,
  ///   - for-каналов в том же X-диапазоне,
  /// плюс зазор `stepY/2`, с капом `target.top − stepY/8`.
  ///
  /// Вертикальные связи (`source.dx ≈ end.dx`) пропускаются — им шина
  /// не нужна. Если таких нет и горизонталей нет — возвращается 0.
  double _busY(FlowchartGraph g, String targetName) {
    if (!identical(_busYCacheGraph, g)) {
      _busYCache.clear();
      _busYCacheGraph = g;
    }
    final cached = _busYCache[targetName];
    if (cached != null) return cached;

    final tgt = g.nodes[targetName];
    if (tgt == null) return 0;
    final endPort = _portPosition(tgt, 'in', outgoing: false);

    double needed = double.negativeInfinity;
    bool hasHorizontal = false;

    for (final c in g.connections) {
      if (c.targetNodeName != targetName) continue;
      if (c.targetPort == 'loopback') continue;
      if (c.sourcePort == 'exit') continue; // exit — свой turnY

      final src = g.nodes[c.sourceNodeName];
      if (src == null) continue;

      final srcPort = _portPosition(src, c.sourcePort, outgoing: true);
      if ((srcPort.dx - endPort.dx).abs() < 0.5) continue; // вертикаль

      // X-диапазон горизонтали этой связи
      double xLo, xHi;
      if (c.sourcePort == 'no') {
        final corridorX = _noCorridorX(g, c.sourceNodeName);
        xLo = math.min(corridorX, endPort.dx);
        xHi = math.max(corridorX, endPort.dx);
      } else {
        xLo = math.min(srcPort.dx, endPort.dx);
        xHi = math.max(srcPort.dx, endPort.dx);
      }

      hasHorizontal = true;

      // Низ источника
      final srcBottom = src.position.dy + nodeSize.height;
      if (srcBottom > needed) needed = srcBottom;

      // Ноды-препятствия в X-диапазоне
      for (final e in g.nodes.entries) {
        if (e.key == targetName) continue;
        final n = e.value;
        final left = n.position.dx;
        final right = left + nodeSize.width;
        if (right < xLo || left > xHi) continue;
        if (n.position.dy >= endPort.dy - 1.0) continue;
        final b = n.position.dy + nodeSize.height;
        if (b > needed) needed = b;
      }

      // For-каналы в том же X-диапазоне
      for (final channelY in _forChannelsInXRange(g, xLo, xHi)) {
        if (channelY >= endPort.dy - 1.0) continue;
        final need = channelY + spacing.loopbackChannelStep;
        if (need > needed) needed = need;
      }
    }

    if (!hasHorizontal) {
      _busYCache[targetName] = 0;
      return 0;
    }

    final cap = endPort.dy - spacing.stepY / 8;
    double result = needed + spacing.stepY / 2;
    if (result > cap) result = cap;

    _busYCache[targetName] = result;
    return result;
  }

  // Позиция порта в координатах холста
  Offset _portPosition(NodeModel n, String port, {required bool outgoing}) {
    final p = n.position;
    final w = nodeSize.width;
    final h = nodeSize.height;

    switch (port) {
      // Точка входа любого блока
      case 'in':
        return p + Offset(w / 2, 0);

      // Выходы, идущие вниз по главной ветке
      case 'out':
      case 'yes':
      case 'body':
        return p + Offset(w / 2, h);

      // Выходы, идущие вправо
      case 'no':
      case 'exit':
        return p + Offset(w, h / 2);

      // Обратная связь тела цикла к For
      case 'loopback':
        return outgoing ? p + Offset(w / 2, h) : p + Offset(0, h / 2);

      // Fallback: по направлению ребра
      default:
        return outgoing ? p + Offset(w / 2, h) : p + Offset(w / 2, 0);
    }
  }

  RoutedConnection _routeDefault(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    if ((start.dx - end.dx).abs() < 0.5) {
      return RoutedConnection(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy),
        const [],
      );
    }

    final busY = _busY(g, c.targetNodeName);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx, busY)
      ..lineTo(end.dx, busY)
      ..lineTo(end.dx, end.dy);

    final arrows = _busArrows(
      g: g,
      c: c,
      dropX: start.dx,
      endX: end.dx,
      busY: busY,
      fallbackAtTarget: true,
    );

    return RoutedConnection(path, arrows);
  }

  RoutedConnection _routeNo(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final corridorX = _noCorridorX(g, c.sourceNodeName);
    final goingRight = end.dx > start.dx + 1.0;

    // ── RD: цель правее источника — обходить нечего, идём напрямую ──
    if (goingRight) {
      debugPrint(
        '[routeNo] ${c.sourceNodeName}--no->${c.targetNodeName} '
        'RD: start=(${start.dx.toStringAsFixed(1)},'
        '${start.dy.toStringAsFixed(1)}) '
        'end=(${end.dx.toStringAsFixed(1)},'
        '${end.dy.toStringAsFixed(1)})',
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      return RoutedConnection(path, const []);
    }
    final busY = _busY(g, c.targetNodeName);

    debugPrint(
      '[routeNo] ${c.sourceNodeName}--no->${c.targetNodeName} '
      'RDL: start=(${start.dx.toStringAsFixed(1)},'
      '${start.dy.toStringAsFixed(1)}) '
      'dropX=${corridorX.toStringAsFixed(1)} '
      'busY=${busY.toStringAsFixed(1)} '
      'end=(${end.dx.toStringAsFixed(1)},'
      '${end.dy.toStringAsFixed(1)})',
    );

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(corridorX, start.dy) // ← corridorX, без shadow
      ..lineTo(corridorX, busY)
      ..lineTo(end.dx, busY)
      ..lineTo(end.dx, end.dy);

    final arrows = _busArrows(
      g: g,
      c: c,
      dropX: corridorX,
      endX: end.dx,
      busY: busY,
    );

    return RoutedConnection(path, arrows);
  }

  /// Y горизонтали For-петли (body или exit → loopback).
  /// Единый источник: и `_routeLoopback`, и `_busYRange` должны
  /// использовать один и тот же расчёт, иначе разойдутся.
  double? _forChannelY(FlowchartGraph g, String forName, String sourcePort) {
    final node = g.nodes[forName];
    if (node == null || node.data is! ForBlock) return null;

    final int pos;
    if (sourcePort == 'body' || sourcePort == 'out') {
      pos = GraphGeometry.innerForCount(g, forName) * 2; // чётные
    } else if (sourcePort == 'exit') {
      pos = GraphGeometry.innerForCount(g, forName) * 2 + 1; // нечётные
    } else {
      return null;
    }

    final forBottom = node.position.dy + nodeSize.height;
    final bodyBottom = GraphGeometry.bodySubtreeBottom(g, forName, nodeSize);
    final baseBottom = math.max(forBottom, bodyBottom);

    return baseBottom +
        spacing.bodyLoopbackDrop +
        pos * spacing.loopbackChannelStep;
  }

  /// Y-ы For-петель, чья горизонталь перекрывает [xLo, xHi].
  /// Горизонталь For-петли идёт от `end.dx - inset` до `startJogX`,
  /// где startJogX ≈ For.right (или чуть правее для exit).
  /// Для перекрытия достаточно пересечения прямоугольника
  /// [For.x, For.right + stepX] с [xLo, xHi] — с запасом.
  List<double> _forChannelsInXRange(FlowchartGraph g, double xLo, double xHi) {
    final ys = <double>[];

    for (final e in g.nodes.entries) {
      if (e.value.data is! ForBlock) continue;

      final forLeft = e.value.position.dx;
      final forRight = forLeft + nodeSize.width;
      // Запас вправо: exit-коридор идёт правее тела на corridorSlotStep
      final zoneHi = forRight + spacing.stepX;
      if (zoneHi < xLo || forLeft > xHi) continue;

      for (final c in g.outgoing[e.key] ?? const <ConnectionData>[]) {
        if (c.targetPort != 'loopback') continue;
        final y = _forChannelY(g, e.key, c.sourcePort);
        if (y != null) ys.add(y);
      }
    }

    return ys;
  }

  // Множество узлов yes-ветки от логики до первой merge-точки с no-веткой
  Set<String> _yesBranchUntilMerge(FlowchartGraph g, String logicName) {
    ConnectionData? yesConn, noConn;
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'yes') yesConn = c;
      if (c.sourcePort == 'no') noConn = c;
    }
    if (yesConn == null || noConn == null) return {};
    if (yesConn.targetNodeName == noConn.targetNodeName) return {};

    // все, достижимое из no-ветки
    final noReach = <String>{};
    final q1 = <String>[noConn.targetNodeName];
    while (q1.isNotEmpty) {
      final cur = q1.removeAt(0);
      if (!noReach.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        q1.add(c.targetNodeName);
      }
    }

    // yes-ветка BFS с остановкой на первой merge-точке
    final result = <String>{};
    final q2 = <String>[yesConn.targetNodeName];
    while (q2.isNotEmpty) {
      final cur = q2.removeAt(0);
      if (noReach.contains(cur)) continue;
      if (g.isEnd(cur)) continue;
      if (!result.add(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        q2.add(c.targetNodeName);
      }
    }
    return result;
  }

  // цель левее источника и это не случай yes+no одного родителя в одну цель
  bool _isRealNoBranch(FlowchartGraph g, ConnectionData c) {
    if (c.sourcePort != 'no') return false;
    if (c.targetPort == 'loopback') return false;
    final src = g.nodes[c.sourceNodeName];
    final tgt = g.nodes[c.targetNodeName];
    if (src == null || tgt == null) return false;
    if (tgt.position.dx >= src.position.dx - 1) return false;

    final hasYesToSame = (g.outgoing[c.sourceNodeName] ?? const []).any(
      (x) => x.sourcePort == 'yes' && x.targetNodeName == c.targetNodeName,
    );
    return !hasYesToSame;
  }

  int _noBranchSlot(FlowchartGraph g, String logicName) {
    final n = g.nodes[logicName];
    if (n == null) return 0;
    int slot = 0;
    for (final c in g.connections) {
      if (c.sourceNodeName == logicName) continue;
      if (!_isRealNoBranch(g, c)) continue;
      final src = g.nodes[c.sourceNodeName];
      if (src == null) continue;
      if ((src.position.dx - n.position.dx).abs() > 1.0) {
        continue; // не тот столбец
      }
      if (src.position.dy <= n.position.dy - 1.0) continue;
      slot++;
    }
    return slot;
  }

  double _noCorridorX(
    FlowchartGraph g,
    String logicName, {
    Set<String>? visiting,
  }) {
    visiting ??= <String>{};
    if (!visiting.add(logicName)) {
      final n = g.nodes[logicName];
      return (n?.position.dx ?? 0) + nodeSize.width;
    }

    final node = g.nodes[logicName];
    if (node == null) {
      visiting.remove(logicName);
      return 0;
    }

    final bas = spacing.corridorGap;
    final corridorGap = nodeSize.width / 6;
    final maxDepth = GraphGeometry.maxForDepth(g);

    double rightX = node.position.dx + nodeSize.width + bas / 2;

    // Обход yes-поддерево (до merge-точки)
    final yesSubtree = _yesBranchUntilMerge(g, logicName);
    for (final childName in yesSubtree) {
      final child = g.nodes[childName];
      if (child == null) continue;

      final blockRight = child.position.dx + nodeSize.width;
      double visualRight = blockRight;

      // For: exit-коридор идет правее правого края
      if (child.data is ForBlock) {
        final ancestors = GraphGeometry.forAncestorCount(g, childName);
        final levels = (maxDepth - ancestors).clamp(0, 10);

        double subRight = blockRight;
        ConnectionData? exitConn;
        for (final c in g.outgoing[childName] ?? const <ConnectionData>[]) {
          if (c.sourcePort == 'exit') {
            exitConn = c;
            break;
          }
        }
        if (exitConn != null && exitConn.targetPort != 'loopback') {
          final sub = _subtreeBounds(
            g,
            childName,
            stopAt: exitConn.targetNodeName,
          );
          if (sub.right > subRight) subRight = sub.right;
        }
        final forCorridor = subRight + bas / 2 * (levels + 1);
        if (forCorridor > visualRight) visualRight = forCorridor;

        debugPrint(
          '[noCorridor/For] $logicName -> child=$childName '
          'blockRight=${blockRight.toStringAsFixed(1)} '
          'subRight=${subRight.toStringAsFixed(1)} '
          'levels=$levels '
          'forCorridor=${forCorridor.toStringAsFixed(1)}',
        );
      }

      if (child.data is LogicBlock) {
        final hasRealNo = (g.outgoing[childName] ?? const []).any((c) {
          if (c.sourcePort != 'no') return false;
          if (c.targetPort == 'loopback') return false;
          final tgt = g.nodes[c.targetNodeName];
          if (tgt == null) return false;
          if (tgt.position.dx > child.position.dx + 1.0) return false;
          return true;
        });
        if (hasRealNo) {
          final childCorridor = _noCorridorX(g, childName, visiting: visiting);
          if (childCorridor > visualRight) visualRight = childCorridor;
        }
      }

      final need = visualRight + corridorGap;
      if (need > rightX) rightX = need;
    }

    rightX += spacing.corridorSlotStep * _noBranchSlot(g, logicName);

    visiting.remove(logicName);
    return rightX;
  }

  // exit: из правого порта For, обход тела цикла справа и снизу
  RoutedConnection _routeExit(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    // final bas = spacing.corridorGap;
    // Локальные границы тела этого For
    final local = _subtreeBounds(g, c.sourceNodeName, stopAt: c.targetNodeName);
    // Глубина: сколько For-предков у данного источника
    // final ancestors = GraphGeometry.forAncestorCount(g, c.sourceNodeName);
    // final maxDepth = GraphGeometry.maxForDepth(g);
    // final levelsFromInner = maxDepth - ancestors;

    // Правый коридор
    // для вложенных - каждый следующий сдвигается на base
    // final rightX = local.right + bas / 2 * (levelsFromInner + 1);
    final rightX = local.right;
    debugPrint('__routeExit $rightX');

    double obstaclesBottom = 0;
    for (final e in g.nodes.entries) {
      if (e.key == c.sourceNodeName) continue;
      if (e.key == c.targetNodeName) continue;
      final n = e.value;
      final left = n.position.dx;
      final right = left + nodeSize.width;
      if (right < end.dx - 1 || left > rightX + 1) continue;
      final bottom = n.position.dy + nodeSize.height;
      if (bottom >= end.dy - 1) continue;
      if (bottom > obstaclesBottom) obstaclesBottom = bottom;
    }

    final channelY = _forChannelY(g, c.sourceNodeName, 'exit');
    final baseBottom = math.max(local.bottom, obstaclesBottom);
    final desired = math.max(
      baseBottom + spacing.bodyLoopbackDrop,
      channelY ?? 0,
    );
    // final desired = baseBottom + spacing.stepY / 8 * levelsFromInner;
    // final desired = local.bottom + spacing.stepY / 4 + depthOffset;
    final cap = end.dy - spacing.stepY / 8;
    final turnY = desired < cap ? desired : cap;

    if (end.dx >= rightX) {
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      final midX = (start.dx + end.dx) / 2;
      return RoutedConnection(path, [ArrowMarker(Offset(midX, start.dy), 0.0)]);
    }

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(rightX, start.dy)
      ..lineTo(rightX, turnY)
      ..lineTo(end.dx, turnY)
      ..lineTo(end.dx, end.dy);

    final arrows = _busArrows(
      g: g,
      c: c,
      dropX: rightX,
      endX: end.dx,
      busY: turnY,
    );
    return RoutedConnection(path, arrows);
  }

  // loopback: вниз -> влево -> вверх -> вправо в For
  RoutedConnection _routeLoopback(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final bas = spacing.stepX / 12;
    final source = g.nodes[c.sourceNodeName];

    // Базовый turnY - чуть ниже источника.
    // double turnY = start.dy + math.max(bas / 2, spacing.stepY / 3);
    double turnY = start.dy + bas * 1.2;

    final maxDepth = GraphGeometry.maxForDepth(g);

    //
    // ─── For.body / For.out → loopback ───
    if (source != null &&
        source.data is ForBlock &&
        (c.sourcePort == 'body' || c.sourcePort == 'out')) {
      final channelY = _forChannelY(g, c.sourceNodeName, c.sourcePort)!;
      if (channelY > turnY) turnY = channelY;

      // Горизонталь For-петли должна идти ниже всех блоков в её X-зоне
      final ownBottom = source.position.dy + nodeSize.height;
      final leftX = end.dx;
      final rightX = source.position.dx + nodeSize.width + spacing.stepX;
      for (final e in g.nodes.entries) {
        if (e.key == c.sourceNodeName) continue;
        if (e.key == c.targetNodeName) continue;
        final n = e.value;
        if (n.position.dx + nodeSize.width < leftX) continue;
        if (n.position.dx > rightX) continue;
        if (n.position.dy < ownBottom - 1.0) continue; // выше For — пропускаем
        if (n.position.dy >= end.dy - 1.0) continue; // ниже цели — пропускаем
        final b = n.position.dy + nodeSize.height + spacing.bodyLoopbackDrop;
        if (b > turnY) turnY = b;
      }
    }

    // ─── For.exit → loopback ───
    if (source != null && source.data is ForBlock && c.sourcePort == 'exit') {
      final channelY = _forChannelY(g, c.sourceNodeName, c.sourcePort)!;
      final bodyBottom = GraphGeometry.bodySubtreeBottom(
        g,
        c.sourceNodeName,
        nodeSize,
      );
      final minForBody = bodyBottom + spacing.bodyLoopbackDrop;
      final desired = math.max(channelY, minForBody);
      if (desired > turnY) turnY = desired;

      // Те же препятствия — блоки в X-зоне
      final leftX = end.dx;
      final rightX = source.position.dx + nodeSize.width + spacing.stepX;
      for (final e in g.nodes.entries) {
        if (e.key == c.sourceNodeName) continue;
        if (e.key == c.targetNodeName) continue;
        final n = e.value;
        if (n.position.dx + nodeSize.width < leftX) continue;
        if (n.position.dx > rightX) continue;
        if (n.position.dy < bodyBottom - 1.0) continue;
        if (n.position.dy >= end.dy - 1.0) continue;
        final b = n.position.dy + nodeSize.height + spacing.bodyLoopbackDrop;
        if (b > turnY) turnY = b;
      }
    }

    if (source != null && source.data is LogicBlock && c.sourcePort == 'no') {
      final srcBottom = source.position.dy + nodeSize.height;
      final yesBottom = GraphGeometry.logicYesSubtreeBottom(
        g,
        c.sourceNodeName,
        nodeSize,
      );
      final minTurnY = math.max(srcBottom, yesBottom);
      // final minTurnY = srcBottom;
      // if (turnY < srcBottom) turnY = srcBottom + bas * 1.2;
      if (turnY < minTurnY) turnY = minTurnY + bas * 1.2;
    }

    if (source != null && source.data is LogicBlock && c.sourcePort == 'yes') {
      final branchBottom = GraphGeometry.logicBranchBottom(
        g,
        c.sourceNodeName,
        nodeSize,
      );
      final desired = branchBottom + bas * 1.2;
      if (desired > turnY) turnY = desired;
    }

    final ancestors = GraphGeometry.forAncestorCount(g, c.targetNodeName);

    final levelsFromInner = maxDepth - ancestors; // 0 у самого внутреннего
    final inset = bas / 2 * (levelsFromInner + 1);

    final isExitPort = c.sourcePort == 'exit';
    double startJogX = start.dx;
    // final startJogX = isEx/2itPort ? start.dx + bas / 2 : start.dx;
    if (isExitPort) {
      final srcAncestors = GraphGeometry.forAncestorCount(g, c.sourceNodeName);
      final srcLevelsFromInner = math.max(0, maxDepth - srcAncestors);
      startJogX = start.dx + bas * (srcLevelsFromInner + 1);
    } else if (source != null &&
        source.data is LogicBlock &&
        c.sourcePort == 'no') {
      final corridor = _noCorridorX(g, c.sourceNodeName);
      if (corridor > startJogX) startJogX = corridor;
    }

    // final vertTopY = start.dy + bas / 2;
    final vertTopY = turnY;
    final vertBottomY = end.dy;
    final midVertY = (vertTopY + vertBottomY) / 2;
    final leftVertX = end.dx - inset;

    double arrowX;
    if (isExitPort) {
      final xLo = math.min(leftVertX, startJogX);
      final xHi = math.max(leftVertX, startJogX);
      double? firstCrossingX;
      for (final other in g.connections) {
        if (identical(other, c)) continue;
        if (other.sourcePort != 'exit' || other.targetPort != 'loopback') {
          continue;
        }
        final otherSrc = g.nodes[other.sourceNodeName];
        if (otherSrc == null || otherSrc.data is! ForBlock) continue;
        final otherStartY = otherSrc.position.dy + nodeSize.height / 2;
        if (otherStartY >= turnY) continue;
        final otherAncestors = GraphGeometry.forAncestorCount(
          g,
          other.sourceNodeName,
        );
        final otherLevels = math.max(0, maxDepth - otherAncestors);
        final otherJogX =
            _portPosition(otherSrc, 'exit', outgoing: true).dx +
            bas * (otherLevels + 1);
        if (otherJogX <= xLo + 0.5 || otherJogX >= xHi - 0.5) continue;
        if (firstCrossingX == null || otherJogX > firstCrossingX) {
          firstCrossingX = otherJogX;
        }
      }
      arrowX = firstCrossingX != null
          ? (firstCrossingX).clamp(xLo + 8.0, xHi - 8.0)
          : (xLo + xHi) / 2;
      debugPrint(
        '[loopbackArrow] ${c.sourceNodeName}--exit->'
        '${c.targetNodeName}.loopback: '
        'turnY=${turnY.toStringAsFixed(1)} '
        'crossing=${firstCrossingX?.toStringAsFixed(1) ?? "none"} '
        'arrowX=${arrowX.toStringAsFixed(1)}',
      );
    } else {
      arrowX = (startJogX + leftVertX) / 2;
    }

    return RoutedConnection(
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(startJogX, start.dy)
        ..lineTo(startJogX, vertTopY)
        ..lineTo(leftVertX, vertTopY)
        ..lineTo(leftVertX, vertBottomY)
        ..lineTo(end.dx, vertBottomY),
      [
        ArrowMarker(Offset(arrowX, vertTopY), -math.pi),
        ArrowMarker(Offset(leftVertX, midVertY), -math.pi / 2),
        ArrowMarker(Offset(end.dx, vertBottomY), 0.0),
      ],
    );
  }

  // Стрелки на горизонтальной шине: возвращает либо пустой список,  либо одну стрелку в правильном месте.
  List<ArrowMarker> _busArrows({
    required FlowchartGraph g,
    required ConnectionData c,
    required double dropX,
    required double endX,
    required double busY,
    bool fallbackAtTarget = false,
  }) {
    final goingLeft = endX < dropX - 0.5;
    final goingRight = endX > dropX + 0.5;
    if (!goingLeft && !goingRight) return const []; // вертикаль

    final xLo = math.min(endX, dropX);
    final xHi = math.max(endX, dropX);
    final xMin = xLo + spacing.arrowInset;
    final xMax = xHi - spacing.arrowInset;

    final events = _mergeDetector.forConnection(g, c);
    if (events.isNotEmpty) {
      final e = events.first;
      final pos = e.arrowPosition(spacing.arrowInset);

      double x;
      if (e.flowLeft) {
        x = e.xMerge;
      } else {
        final lo = xLo + 1.0;
        final hi = math.min(e.xMerge - 1.0, xHi - 1.0);
        x = hi > lo ? pos.dx.clamp(lo, hi) : e.xMerge - 1.0;
      }

      debugPrint(
        '[busArrow/merge] ${c.sourceNodeName}--${c.sourcePort}->'
        '${c.targetNodeName}: '
        'flowLeft=${e.flowLeft} '
        'xMerge=${e.xMerge.toStringAsFixed(1)} '
        'raw=${pos.dx.toStringAsFixed(1)} '
        'clamped=${x.toStringAsFixed(1)} '
        'range=[${xLo.toStringAsFixed(1)},${xHi.toStringAsFixed(1)}]',
      );

      return [ArrowMarker(Offset(x, busY), e.arrowAngle())];
    }

    if (!fallbackAtTarget) return const [];

    final fallbackX = goingLeft
        ? (endX + spacing.corridorGap).clamp(xMin, xMax)
        : (endX - spacing.corridorGap).clamp(xMin, xMax);
    return [ArrowMarker(Offset(fallbackX, busY), goingLeft ? math.pi : 0.0)];
  }

  double _dropXOf(FlowchartGraph g, ConnectionData other, NodeModel otherSrc) {
    if (other.sourcePort == 'no') {
      final tgt = g.nodes[other.targetNodeName];
      if (tgt == null) return otherSrc.position.dx + nodeSize.width;
      final endX = _portPosition(tgt, 'in', outgoing: false).dx;
      final rightX = _noCorridorX(g, other.sourceNodeName);
      return endX < rightX - 1.0 ? rightX : endX;
    }
    return _portPosition(otherSrc, other.sourcePort, outgoing: true).dx;
  }

  // Нижняя и правая границы поддерева, начиная с rootName
  ({double bottom, double right}) _subtreeBounds(
    FlowchartGraph g,
    String rootName, {
    required String stopAt,
    Set<String>? visiting,
  }) {
    visiting ??= <String>{};

    if (!visiting.add(rootName)) {
      final n = g.nodes[rootName];
      if (n == null) return (bottom: 0, right: 0);
      return (
        bottom: n.position.dy + nodeSize.height,
        right: n.position.dx + nodeSize.width,
      );
    }

    final bas = spacing.stepX / 12;
    final maxDepth = GraphGeometry.maxForDepth(g);

    // final stepXExtra = spacing.stepX - nodeSize.width;
    double bottom = -double.infinity;
    double right = -double.infinity;
    final visited = <String>{};
    final queue = <String>[rootName];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (cur == stopAt) continue;
      final n = g.nodes[cur];
      if (n == null) continue;

      final b = n.position.dy + nodeSize.height;
      double r = n.position.dx + nodeSize.width;

      if (n.data is LogicBlock) {
        final hasRealNo = (g.outgoing[cur] ?? const <ConnectionData>[]).any((
          c,
        ) {
          if (c.sourcePort != 'no' || c.targetPort == 'loopback') return false;
          final tgt = g.nodes[c.targetNodeName];
          return tgt != null && tgt.position.dx <= n.position.dx + 1.0;
        });
        if (hasRealNo) {
          final corridor = _noCorridorX(g, cur, visiting: visiting);
          if (corridor > r) r = corridor;
        }
      }

      if (n.data is ForBlock) {
        final outs = g.outgoing[cur] ?? const <ConnectionData>[];
        final exitConn = outs.firstWhereOrNull((c) => c.sourcePort == 'exit');
        final bodyConn = outs.firstWhereOrNull((c) => c.sourcePort == 'body');

        if (exitConn != null &&
            exitConn.targetPort != 'loopback' &&
            bodyConn != null &&
            bodyConn.targetNodeName != cur) {
          // Правый край тела + зазор на уровень вложенности
          final bodyBounds = _subtreeBounds(
            g,
            bodyConn.targetNodeName,
            stopAt: exitConn.targetNodeName,
            visiting: visiting,
          );
          final ancestors = GraphGeometry.forAncestorCount(g, cur);
          final levels = math.max(0, maxDepth - ancestors);
          final exitCorridor = bodyBounds.right + bas * (levels + 1);
          if (exitCorridor > r) r = exitCorridor;
        }
      }

      if (b > bottom) bottom = b;
      if (r > right) right = r;

      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    visiting.remove(rootName);
    return (bottom: bottom, right: right);
  }
}
