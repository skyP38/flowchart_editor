import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import 'flowchart_graph.dart';
import 'layout_engine.dart';
import 'dart:math' as math;
import 'dart:core';
import '../models/flow_models.dart';

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

  void resetCache() {
    _busYCache.clear();
    _busYCacheGraph = null;
  }

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

    double minX = double.infinity;
    double maxX = -double.infinity;
    double maxSrcBottom = double.negativeInfinity;
    bool hasHorizontal = false;

    for (final c in g.connections) {
      if (c.targetNodeName != targetName) continue;
      if (c.targetPort == 'loopback') continue;
      final src = g.nodes[c.sourceNodeName];
      if (src == null) continue;

      final srcPort = _portPosition(src, c.sourcePort, outgoing: true);
      if ((srcPort.dx - endPort.dx).abs() < 0.5) {
        continue;
      }
      hasHorizontal = true;
      if (srcPort.dx < minX) minX = srcPort.dx;
      if (srcPort.dx > maxX) maxX = srcPort.dx;
      final srcBottom = src.position.dy + nodeSize.height;
      if (srcBottom > maxSrcBottom) maxSrcBottom = srcBottom;
    }

    if (!hasHorizontal) {
      _busYCache[targetName] = 0;
      return 0;
    }
    if (endPort.dx < minX) minX = endPort.dx;
    if (endPort.dx > maxX) maxX = endPort.dx;

    // Шина должна лежать ниже всех блоков в горизонтальной полосе
    double maxBottom = maxSrcBottom;
    for (final e in g.nodes.entries) {
      if (e.key == targetName) continue;
      final n = e.value;
      final left = n.position.dx;
      final right = left + nodeSize.width;
      if (right < minX || left > maxX) continue;
      if (n.position.dy >= endPort.dy - 1.0) continue;
      final b = n.position.dy + nodeSize.height;
      if (b > maxBottom) maxBottom = b;
    }

    final cap = endPort.dy - spacing.stepY / 8;
    double result = maxBottom + spacing.stepY / 2;
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

  // стрелки на общей шине: ставим за gap до ближайшего вертикального спуска
  double _arrowXOnBus(
    FlowchartGraph g,
    ConnectionData c,
    double myDropX,
    double myEndX,
  ) {
    final goingLeft = myEndX < myDropX - 0.5;
    final gap = spacing.stepX / 6;

    final tgt = g.nodes[c.targetNodeName];
    if (tgt == null) return myEndX;
    final tgtEnd = _portPosition(tgt, 'in', outgoing: false);

    // Следующая вертикаль
    double best = myEndX;

    for (final other in g.connections) {
      if (identical(other, c)) continue;
      if (other.targetNodeName != c.targetNodeName) continue;
      if (other.targetPort == 'loopback') continue;
      final otherSrc = g.nodes[other.sourceNodeName];
      if (otherSrc == null) continue;

      double dropX;
      if (other.sourcePort == 'no' && otherSrc.position.dx > tgtEnd.dx + 1) {
        dropX = _noCorridorX(g, other.sourceNodeName);
      } else {
        dropX = _portPosition(otherSrc, other.sourcePort, outgoing: true).dx;
      }

      if (goingLeft) {
        if (dropX > myEndX + 0.5 && dropX < myDropX - 0.5) {
          if (dropX > best) best = dropX;
        }
      } else {
        if (dropX < myEndX - 0.5 && dropX > myDropX + 0.5) {
          if (dropX < best) best = dropX;
        }
      }
    }

    return goingLeft ? best + gap : best - gap;
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
        [],
      );
    }

    final busY = _busY(g, c.targetNodeName);
    debugPrint(
      '[routeDefault] ${c.sourceNodeName}--${c.sourcePort}->'
      '${c.targetNodeName}: '
      'dropX=${start.dx.toStringAsFixed(1)} '
      'busY=${busY.toStringAsFixed(1)} '
      'endX=${end.dx.toStringAsFixed(1)}',
    );
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx, busY)
      ..lineTo(end.dx, busY)
      ..lineTo(end.dx, end.dy);

    final arrowX = _arrowXOnBus(g, c, start.dx, end.dx);
    final towardLeft = end.dx < start.dx;
    return RoutedConnection(path, [
      ArrowMarker(Offset(arrowX, busY), towardLeft ? math.pi : 0.0),
    ]);
  }

  RoutedConnection _routeNo(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final busY = _busY(g, c.targetNodeName);

    final rightX = _noCorridorX(g, c.sourceNodeName);

    // Цель слева
    if (end.dx < rightX - 1.0) {
      debugPrint(
        '[routeNo] ${c.sourceNodeName}--no->${c.targetNodeName} '
        'RDL: start=(${start.dx.toStringAsFixed(1)},'
        '${start.dy.toStringAsFixed(1)}) '
        // 'dropX=${rightX.toStringAsFixed(1)} '
        'busY=${busY.toStringAsFixed(1)} '
        'end=(${end.dx.toStringAsFixed(1)},'
        '${end.dy.toStringAsFixed(1)})',
      );
      final rightX = _noCorridorX(g, c.sourceNodeName);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(rightX, start.dy)
        ..lineTo(rightX, busY)
        ..lineTo(end.dx, busY)
        ..lineTo(end.dx, end.dy);

      final arrows = _busArrows(
        g: g,
        c: c,
        dropX: rightX,
        endX: end.dx,
        busY: busY,
      );
      return RoutedConnection(path, arrows);
    }

    debugPrint(
      '[routeNo] ${c.sourceNodeName}--no->${c.targetNodeName} '
      'RD: start=(${start.dx.toStringAsFixed(1)},'
      '${start.dy.toStringAsFixed(1)}) '
      'dropX=${end.dx.toStringAsFixed(1)} '
      'end=(${end.dx.toStringAsFixed(1)},'
      '${end.dy.toStringAsFixed(1)})',
    );
    // Цель справа: вправо-вниз
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    return RoutedConnection(path, []);
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

    final bas = spacing.stepX / 6;
    final corridorGap = nodeSize.width / 6;
    final maxDepth = LayoutEngine.maxForDepth(g);

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
        final ancestors = _forAncestorCount(g, childName);
        final levels = (maxDepth - ancestors).clamp(0, 10);
        final forCorridor = blockRight + bas / 2 * (levels + 1);
        if (forCorridor > visualRight) visualRight = forCorridor;
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

    rightX += bas / 2 * _noBranchSlot(g, logicName);

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
    final bas = spacing.stepX / 6;
    // Локальные границы тела этого For
    final local = _subtreeBounds(g, c.sourceNodeName, stopAt: c.targetNodeName);
    // Глубина: сколько For-предков у данного источника
    final ancestors = _forAncestorCount(g, c.sourceNodeName);
    final maxDepth = LayoutEngine.maxForDepth(g);
    final levelsFromInner = maxDepth - ancestors;

    // Правый коридор
    // для вложенных - каждый следующий сдвигается на base
    final rightX = local.right + bas / 2 * (levelsFromInner + 1);

    final depthOffset = spacing.stepY / 6 * levelsFromInner;
    final desired = local.bottom + spacing.stepY / 4 + depthOffset;
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
    double turnY = start.dy + bas / 2;

    if (source != null && source.data is ForBlock && c.sourcePort == 'exit') {
      final bodyBottom = _bodySubtreeBottom(g, c.sourceNodeName);
      final desired = bodyBottom + bas;
      if (desired > turnY) turnY = desired;
    }

    final ancestors = _forAncestorCount(g, c.targetNodeName);
    final maxDepth = LayoutEngine.maxForDepth(g);
    final levelsFromInner = maxDepth - ancestors; // 0 у самого внутреннего
    final inset = bas / 2 * (levelsFromInner + 1);

    // final vertTopY = start.dy + bas / 2;
    final vertTopY = turnY;
    final vertBottomY = end.dy;
    final midVertY = (vertTopY + vertBottomY) / 2;

    return RoutedConnection(
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, vertTopY)
        ..lineTo(end.dx - inset, vertTopY)
        ..lineTo(end.dx - inset, vertBottomY)
        ..lineTo(end.dx, vertBottomY),
      [
        ArrowMarker(
          Offset((start.dx + end.dx - inset) / 2, vertTopY),
          -math.pi,
        ),
        ArrowMarker(Offset(end.dx - inset, midVertY), -math.pi / 2),
        ArrowMarker(Offset(end.dx, vertBottomY), 0.0),
      ],
    );
  }

  double _bodySubtreeBottom(FlowchartGraph g, String forName) {
    final bodyConn = (g.outgoing[forName] ?? const []).firstWhereOrNull(
      (c) => c.sourcePort == 'body',
    );
    if (bodyConn == null) return 0;
    if (bodyConn.targetNodeName == forName) {
      final n = g.nodes[forName];
      return n == null ? 0 : n.position.dy + nodeSize.height;
    }
    final visited = <String>{};
    final queue = <String>[bodyConn.targetNodeName];
    double maxBottom = 0;
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      final n = g.nodes[cur];
      if (n == null) continue;
      final bottom = n.position.dy + nodeSize.height;
      if (bottom > maxBottom) maxBottom = bottom;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit' && c.sourceNodeName == forName) continue;
        queue.add(c.targetNodeName);
      }
    }
    return maxBottom;
  }

  // Стрелки на горизонтальной шине: возвращает либо пустой список,  либо одну стрелку в правильном месте.
  List<ArrowMarker> _busArrows({
    required FlowchartGraph g,
    required ConnectionData c,
    required double dropX,
    required double endX,
    required double busY,
  }) {
    // Стрелки - только при движении справа налево
    if (endX >= dropX - 0.5) return const [];

    final horizontalLen = (dropX - endX).abs();
    if (horizontalLen < 24) return const [];

    final xLo = endX;
    final xHi = dropX;

    double? firstCrossingX;
    for (final other in g.connections) {
      if (identical(other, c)) continue;
      if (other.targetNodeName != c.targetNodeName) continue;
      if (other.targetPort == 'loopback') continue;

      final otherSrc = g.nodes[other.sourceNodeName];
      if (otherSrc == null) continue;

      final otherDropX = _dropXOf(g, other, otherSrc);
      if (otherDropX <= xLo + 0.5 || otherDropX >= xHi - 0.5) continue;

      // Проверяем, что вертикаль other покрывает наш busY.
      final span = _otherVerticalSpan(g, other, otherSrc);
      if (span == null) continue;
      if (busY < span.start - 0.5 || busY > span.end + 0.5) continue;

      debugPrint(
        '[busArrow] ${c.sourceNodeName}--${c.sourcePort}->'
        '${c.targetNodeName}: crossing with '
        '${other.sourceNodeName}--${other.sourcePort} '
        'dropX=${otherDropX.toStringAsFixed(1)} '
        'span=[${span.start.toStringAsFixed(1)},'
        '${span.end.toStringAsFixed(1)}]',
      );

      if (firstCrossingX == null || otherDropX > firstCrossingX) {
        firstCrossingX = otherDropX;
      }
    }

    double arrowX;
    if (firstCrossingX != null) {
      arrowX = firstCrossingX;
    } else {
      arrowX = (xLo + xHi) / 2;
    }

    final clampedX = arrowX.clamp(xLo + 8.0, xHi - 8.0);

    debugPrint(
      '[busArrow] ${c.sourceNodeName}--${c.sourcePort}->'
      '${c.targetNodeName}: '
      'busY=${busY.toStringAsFixed(1)} '
      'xLo=${xLo.toStringAsFixed(1)} xHi=${xHi.toStringAsFixed(1)} '
      'nearest=${firstCrossingX?.toStringAsFixed(1) ?? 'none'} '
      'arrowX=${arrowX.toStringAsFixed(1)} '
      'clamped=${clampedX.toStringAsFixed(1)}'
      '${clampedX != arrowX ? " (CLAMPED)" : ""}',
    );
    return [ArrowMarker(Offset(clampedX, busY), math.pi)];
  }

  // Y-диапазон start, end, который занимает вертикальная часть связи other
  ({double start, double end})? _otherVerticalSpan(
    FlowchartGraph g,
    ConnectionData other,
    NodeModel otherSrc,
  ) {
    final tgt = g.nodes[other.targetNodeName];
    if (tgt == null) return null;
    final targetTop = _portPosition(tgt, 'in', outgoing: false).dy;

    if (other.sourcePort == 'no') {
      final endX = _portPosition(tgt, 'in', outgoing: false).dx;
      final rightX = _noCorridorX(g, other.sourceNodeName);
      if (endX >= rightX - 1.0) return null;

      final noPortY = _portPosition(otherSrc, 'no', outgoing: true).dy;
      final otherBusY = _busY(g, other.targetNodeName);
      return (
        start: math.min(noPortY, otherBusY),
        end: math.max(noPortY, otherBusY),
      );
    }

    final port = _portPosition(otherSrc, other.sourcePort, outgoing: true);
    final y1 = port.dy;
    final y2 = other.sourcePort == 'yes' || other.sourcePort == 'exit'
        ? targetTop
        : targetTop;
    return (start: math.min(y1, y2), end: math.max(y1, y2));
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

  // Сколько For-предков имеет forName
  // 0 - внешний цикл, 1 - вложенный в него, и т.д.
  int _forAncestorCount(FlowchartGraph g, String forName) {
    int count = 0;
    String cur = forName;
    final visited = <String>{forName};

    while (true) {
      String? bestParent;
      int bestSize = 1 << 30;

      for (final c in g.connections) {
        if (c.sourcePort != 'body') continue;
        if (visited.contains(c.sourceNodeName)) continue;

        // Прямой предок
        if (c.targetNodeName == cur) {
          bestParent = c.sourceNodeName;
          bestSize = 0;
          break;
        }

        // Косвенный - только если он ближайший (минимальное поддерево)
        final sub = _subtreeNodes(g, c.targetNodeName);
        if (sub.contains(cur) && sub.length < bestSize) {
          bestSize = sub.length;
          bestParent = c.sourceNodeName;
        }
      }

      if (bestParent == null) break;
      visited.add(bestParent);
      count++;
      cur = bestParent;
    }
    return count;
  }

  // Все узлы, достижимые из root по обычным ребрам (без loopback)
  Set<String> _subtreeNodes(FlowchartGraph g, String root) {
    final result = <String>{};
    void dfs(String n) {
      if (result.contains(n)) return;
      result.add(n);
      if (g.isEnd(n)) return;
      for (final c in g.outgoing[n] ?? const []) {
        if (c.targetPort == 'loopback') continue;
        dfs(c.targetNodeName);
      }
    }

    dfs(root);
    return result;
  }

  // Нижняя и правая границы поддерева, начиная с rootName
  ({double bottom, double right}) _subtreeBounds(
    FlowchartGraph g,
    String rootName, {
    required String stopAt,
  }) {
    final stepXExtra = spacing.stepX - nodeSize.width;
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

      // Габарит по X: правый край + коридор исходящей no-ветки
      final children = g.outgoing[cur] ?? const [];
      final hasNo = children.any(
        (c) => c.sourcePort == 'no' && c.targetNodeName != stopAt,
      );
      if (hasNo) r += stepXExtra / 2;

      if (b > bottom) bottom = b;
      if (r > right) right = r;

      for (final c in children) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return (bottom: bottom, right: right);
  }
}
