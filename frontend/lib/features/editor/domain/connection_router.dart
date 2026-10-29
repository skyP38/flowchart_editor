import 'package:flutter/material.dart';
// import 'package:collection/collection.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import 'flowchart_graph.dart';
import 'layout_engine.dart';
import 'dart:math' as math;
import 'dart:core';
import 'dart:ui';
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
      // 'yes' => _routeYes(start, end, g, conn),
      // 'body' => _routeBody(start, end, g, conn),
      'exit' => _routeExit(start, end, g, conn),
      _ => _routeDefault(start, end, g, conn),
    };
  }

  // double _pairGapValue() => spacing.stepX / 12;

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

    // Собираем все ГОРИЗОНТАЛЬНЫЕ источники к этому target
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
        continue; // вертикальная — не в шине
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

  // double _finalNoY(FlowchartGraph g, ConnectionData c) {
  //   final cached = _noYCache[c];
  //   if (cached != null) return cached;

  //   final myMetric = _outerMetric(g, c);
  //   final src = g.nodes[c.sourceNodeName];
  //   final tgt = g.nodes[c.targetNodeName];
  //   if (src == null || tgt == null) return 0;

  //   final endPort = _portPosition(tgt, 'in', outgoing: false);
  //   final hasYesToSame = (g.outgoing[c.sourceNodeName] ?? const []).any(
  //     (x) => x.sourcePort == 'yes' && x.targetNodeName == c.targetNodeName,
  //   );

  //   // ── Своя «естественная» Y ──
  //   double baseY;
  //   if (hasYesToSame) {
  //     final yesStart = _portPosition(src, 'yes', outgoing: true);

  //     if ((yesStart.dx - endPort.dx).abs() < 0.5) {
  //       final corridorLeft = yesStart.dx - nodeSize.width / 2;
  //       final corridorRight = yesStart.dx + nodeSize.width / 2;

  //       double maxBottom = yesStart.dy;
  //       for (final e in g.nodes.entries) {
  //         if (e.key == c.sourceNodeName) continue;
  //         if (e.key == c.targetNodeName) continue;
  //         final n = e.value;
  //         final left = n.position.dx;
  //         final right = left + nodeSize.width;
  //         if (right < corridorLeft || left > corridorRight) continue;
  //         // Блоки выше источника или ниже цели не мешают
  //         if (n.position.dy + nodeSize.height <= yesStart.dy) continue;
  //         if (n.position.dy >= endPort.dy - 1.0) continue;
  //         final b = n.position.dy + nodeSize.height;
  //         if (b > maxBottom) maxBottom = b;
  //       }

  //       final shortCap = endPort.dy - 2 * _pairGapValue();
  //       final shortNoY = math.min(maxBottom + _pairGapValue(), shortCap);
  //       _noYCache[c] = shortNoY;
  //       return shortNoY;
  //     }
  //     baseY = _directMidYFromPorts(yesStart, endPort, g, c) + _pairGapValue();
  //   } else {
  //     final startPort = _portPosition(src, 'no', outgoing: true);
  //     final rightX = _noCorridorX(g, c.sourceNodeName);
  //     final minX = endPort.dx < startPort.dx ? endPort.dx : startPort.dx;
  //     double maxBottom = startPort.dy;
  //     for (final e in g.nodes.entries) {
  //       if (e.key == c.targetNodeName) continue;
  //       final n = e.value;
  //       final left = n.position.dx;
  //       final right = left + nodeSize.width;
  //       if (right < minX || left > rightX) continue;
  //       if (n.position.dy >= endPort.dy - 1.0) continue;
  //       final bottom = n.position.dy + nodeSize.height;
  //       if (bottom > maxBottom) maxBottom = bottom;
  //     }
  //     baseY = maxBottom + _pairGapValue();
  //   }

  //   // ── Поднимаемся под каждой внутренней веткой ──
  //   double result = baseY;
  //   for (final other in g.connections) {
  //     if (identical(other, c)) continue;
  //     if (other.sourcePort != 'no') continue;
  //     if (other.targetPort == 'loopback') continue;
  //     if (other.targetNodeName != c.targetNodeName) continue;
  //     if (_outerMetric(g, other) >= myMetric - 0.5) continue;

  //     final innerY = _finalNoY(g, other);
  //     final extra = hasYesToSame ? 2 * _pairGapValue() : _pairGapValue();
  //     if (innerY + extra > result) result = innerY + extra;
  //     // if (innerY + _pairGapValue() > result) {
  //     //   result = innerY + _pairGapValue();
  //     // }
  //   }

  //   final cap = endPort.dy - spacing.stepY / 8;
  //   if (result > cap) result = cap;

  //   _noYCache[c] = result;
  //   return result;
  // }

  // Позиция порта в координатах холста
  Offset _portPosition(NodeModel n, String port, {required bool outgoing}) {
    final p = n.position;
    final w = nodeSize.width;
    final h = nodeSize.height;

    switch (port) {
      // Точка входа любого блока
      case 'in':
        return p + Offset(w / 2, 0);

      // Выходы, идущие вниз по «главной» ветке
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

  /// X стрелки на общей шине: ставим за [gap] до ближайшего вертикального
  /// спуска (другого соединения к тому же target, либо самого target),
  /// который встретится по пути от нашего спуска к target.
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

    // «Следующая вертикаль» — минимум по расстоянию в направлении движения.
    // Если между мной и target ничего нет, то это вертикаль самого target.
    double best = myEndX;

    for (final other in g.connections) {
      if (identical(other, c)) continue;
      if (other.targetNodeName != c.targetNodeName) continue;
      if (other.targetPort == 'loopback') continue;
      final otherSrc = g.nodes[other.sourceNodeName];
      if (otherSrc == null) continue;

      double dropX;
      if (other.sourcePort == 'no' && otherSrc.position.dx > tgtEnd.dx + 1) {
        dropX = _noCorridorX(g, other.sourceNodeName); // реальный no-коридор
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
        [ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2)],
      );
    }

    final busY = _busY(g, c.targetNodeName);
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

  // На общей горизонтали — стрелка «перед слиянием», т.е. со стороны источника.
  //   final towardTargetIsLeft = end.dx < start.dx;
  //   final busArrow = ArrowMarker(
  //     Offset(
  //       start.dx + (towardTargetIsLeft ? -1 : 1) * spacing.stepX / 6,
  //       busY,
  //     ),
  //     towardTargetIsLeft ? math.pi : 0.0,
  //   );
  //   final portArrow = ArrowMarker(
  //     Offset(end.dx, end.dy - spacing.stepY / 8),
  //     math.pi / 2,
  //   );
  //   return RoutedConnection(path, [busArrow, portArrow]);
  // }

  RoutedConnection _routeNo(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final busY = _busY(g, c.targetNodeName);
    // ── В пределах одного столбца: прямой L, без коридора и без шины ──
    if ((start.dx - end.dx).abs() < nodeSize.width * 0.6) {
      final y = (busY > start.dy && busY < end.dy)
          ? busY
          : start.dy + spacing.stepY / 4;

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, y)
        ..lineTo(end.dx, y)
        ..lineTo(end.dx, end.dy);

      // final y = end.dy - spacing.stepY / 8;
      // final path = Path()
      //   ..moveTo(start.dx, start.dy)
      //   ..lineTo(start.dx, end.dy - spacing.stepY / 8)
      //   ..lineTo(end.dx, end.dy - spacing.stepY / 8)
      //   ..lineTo(end.dx, end.dy);
      final towardLeft = end.dx < start.dx;
      final arrowX = _arrowXOnBus(g, c, start.dx, end.dx);

      // final midX = (start.dx + end.dx) / 2;
      return RoutedConnection(path, [
        ArrowMarker(Offset(arrowX, y), towardLeft ? math.pi : 0.0),
      ]);
      // return RoutedConnection(path, [
      //   ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2),
      // ]);
    }

    // final busY = _busY(g, c.targetNodeName);

    if (end.dx < start.dx - 1.0) {
      final rightX = _noCorridorX(g, c.sourceNodeName);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(rightX, start.dy)
        ..lineTo(rightX, busY)
        ..lineTo(end.dx, busY)
        ..lineTo(end.dx, end.dy);
      final arrowX = _arrowXOnBus(g, c, rightX, end.dx);
      return RoutedConnection(path, [
        ArrowMarker(Offset(arrowX, busY), math.pi),
      ]);
    }

    // final targetIsLeft = end.dx < start.dx - 1.0;

    // if (targetIsLeft) {
    //   // Цель слева: правый коридор обхода → вниз → общая шина → в порт
    //   final rightX = _noCorridorX(g, c.sourceNodeName);
    //   final path = Path()
    //     ..moveTo(start.dx, start.dy)
    //     ..lineTo(rightX, start.dy)
    //     ..lineTo(rightX, busY)
    //     ..lineTo(end.dx, busY)
    //     ..lineTo(end.dx, end.dy);
    //   return RoutedConnection(path, [
    //     ArrowMarker(Offset(start.dx - spacing.stepX / 6, start.dy), math.pi),
    //     ArrowMarker(Offset(end.dx + spacing.stepX / 6, busY), math.pi),
    //     ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2),
    //   ]);
    // }

    // Цель справа: вправо-вниз (без промежуточной шины)
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    return RoutedConnection(path, [
      ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2),
    ]);
  }

  // Path _routeDefault(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) {
  //   if ((start.dx - end.dx).abs() < 0.5) {
  //     return Path()
  //       ..moveTo(start.dx, start.dy)
  //       ..lineTo(end.dx, end.dy);
  //   }
  //   final busY = _busY(g, c.targetNodeName);
  //   return Path()
  //     ..moveTo(start.dx, start.dy)
  //     ..lineTo(start.dx, busY)
  //     ..lineTo(end.dx, busY)
  //     ..lineTo(end.dx, end.dy);
  // }

  // Path _routeYes(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) => _routeDefault(start, end, g, c);

  // Path _routeBody(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) => _routeDefault(start, end, g, c);

  // Path _routeNo(Offset start, Offset end, FlowchartGraph g, ConnectionData c) {
  //   if ((start.dx - end.dx).abs() < 0.5) {
  //     return Path()
  //       ..moveTo(start.dx, start.dy)
  //       ..lineTo(end.dx, end.dy);
  //   }
  //   final busY = _busY(g, c.targetNodeName);
  //   final targetIsLeft = end.dx < start.dx - 1.0;

  //   if (targetIsLeft) {
  //     // Правый коридор, чтобы обойти цепочку в своём столбце
  //     final rightX = _noCorridorX(g, c.sourceNodeName);
  //     return Path()
  //       ..moveTo(start.dx, start.dy)
  //       ..lineTo(rightX, start.dy)
  //       ..lineTo(rightX, busY)
  //       ..lineTo(end.dx, busY)
  //       ..lineTo(end.dx, end.dy);
  //   }
  //   return Path()
  //     ..moveTo(start.dx, start.dy)
  //     ..lineTo(start.dx, busY)
  //     ..lineTo(end.dx, busY)
  //     ..lineTo(end.dx, end.dy);
  // }

  //  маршруты
  // Обычный выход/yes: вертикально вниз
  // Path _routeDefault(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) {
  //   final path = Path()..moveTo(start.dx, start.dy);
  //   if ((start.dx - end.dx).abs() < 0.5) {
  //     path.lineTo(end.dx, end.dy);
  //     return path;
  //   }

  //   // Разные колонки. Нужно выбрать Y, на котором горизонтальный сдвиг
  //   // и последующий спуск в целевую колонку не пересекут ни одного блока.
  //   final minX = start.dx < end.dx ? start.dx : end.dx;
  //   final maxX = start.dx < end.dx ? end.dx : start.dx;

  //   double maxBottom = start.dy;
  //   for (final e in g.nodes.entries) {
  //     if (e.key == c.targetNodeName) continue;
  //     final n = e.value;
  //     final left = n.position.dx;
  //     final right = n.position.dx + nodeSize.width;

  //     // Блок должен пересекаться с горизонтальным коридором
  //     if (right < minX || left > maxX) continue;
  //     // Блоки на уровне цели или ниже — не мешают
  //     if (n.position.dy >= end.dy - 1.0) continue;

  //     final bottom = n.position.dy + nodeSize.height;
  //     // Блоки целиком выше стартового порта — тоже не мешают
  //     if (bottom <= start.dy) continue;
  //     if (bottom > maxBottom) maxBottom = bottom;
  //   }

  //   final desired = maxBottom + spacing.stepY / 2;
  //   final cap = end.dy - spacing.stepY / 8;
  //   double midY = desired < cap ? desired : cap;

  //   final forbidden = <({double min, double max})>[];
  //   for (final other in g.connections) {
  //     if (identical(other, c)) continue;
  //     if (other.targetPort == 'loopback') continue;
  //     if (other.sourcePort != 'no') continue;
  //     final otherSrc = g.nodes[other.sourceNodeName];
  //     if (otherSrc == null) continue;

  //     final noPort = _portPosition(otherSrc, 'no', outgoing: true);
  //     if (noPort.dx > minX && noPort.dx < maxX) {
  //       final otherNoY = _finalNoY(g, other);
  //       if (otherNoY > noPort.dy) {
  //         forbidden.add((min: noPort.dy, max: otherNoY));
  //       }
  //     }

  //     final hasYesToSame = (g.outgoing[other.sourceNodeName] ?? const []).any(
  //       (x) =>
  //           x.sourcePort == 'yes' && x.targetNodeName == other.targetNodeName,
  //     );
  //     if (hasYesToSame) {
  //       final yesPort = _portPosition(otherSrc, 'yes', outgoing: true);
  //       if (yesPort.dx > minX && yesPort.dx < maxX) {
  //         final yesY = _finalNoY(g, other) - _pairGapValue();
  //         if (yesY > yesPort.dy) {
  //           forbidden.add((min: yesPort.dy, max: yesY));
  //         }
  //       }
  //     }
  //   }

  //   // Если midY попал в запретную полосу — двигаем вниз до её конца.
  //   int safety = 0;
  //   while (safety < 20) {
  //     safety++;
  //     final conflicts = forbidden
  //         .where((f) => midY > f.min && midY < f.max)
  //         .toList();
  //     if (conflicts.isEmpty) break;
  //     final bottomMax = conflicts.map((f) => f.max).reduce(math.max);
  //     final nextY = bottomMax + spacing.stepX / 24;
  //     if (nextY >= cap) break;
  //     midY = nextY;
  //   }

  //   path
  //     ..lineTo(start.dx, midY)
  //     ..lineTo(end.dx, midY)
  //     ..lineTo(end.dx, end.dy);

  //   return path;
  // }

  // Path _routeYes(Offset start, Offset end, FlowchartGraph g, ConnectionData c) {
  //   final hasNoToSame = (g.outgoing[c.sourceNodeName] ?? const []).any(
  //     (x) => x.sourcePort == 'no' && x.targetNodeName == c.targetNodeName,
  //   );
  //   if (hasNoToSame) return _routeYesWithMerge(start, end, g, c);
  //   return _routeDefault(start, end, g, c);
  // }

  // Path _routeYesWithMerge(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) {
  //   // Найти парную no (для _pairYesY)
  //   final noConn = (g.outgoing[c.sourceNodeName] ?? const []).firstWhere(
  //     (x) => x.sourcePort == 'no' && x.targetNodeName == c.targetNodeName,
  //   );

  //   // final noY = _finalNoY(g, noConn);
  //   // final yesY = noY - _pairGapValue();
  //   //
  //   // FlowchartGraph? _busyYCacheGraph;
  //   // final Map<String, double> _busYCache = {};

  //   // void _ensureCaches(FlowchartGraph g) {
  //   //   if (!identical(_busYCacheGraph, g)) {
  //   //     _busYCache.clear();
  //   //     _busYCacheGraph = g;
  //   //   }
  //   // }

  //   // void resetCache() {
  //   //   _busYCache.clear();
  //   //   _busYCacheGraph = null;
  //   // }

  //   // final yesY = _pairYesY(g, noConn);

  //   // Edge case: если наш start.dx лежит в X-полосе какого-то внутреннего
  //   // no-коридора — детурим правее этого коридора.
  //   final corridorGap = nodeSize.width / 6;
  //   double? detourX;
  //   for (final other in g.connections) {
  //     if (other.sourcePort != 'no') continue;
  //     if (other.targetPort == 'loopback') continue;
  //     if (other.targetNodeName != c.targetNodeName) continue;
  //     if (_noBranchOuterCount(g, other) >= _noBranchOuterCount(g, noConn)) {
  //       continue;
  //     }
  //     final innerCorridorX = _computeCorridorX(g, other);
  //     if (start.dx < innerCorridorX && start.dx > end.dx) {
  //       final candidate = innerCorridorX + corridorGap;
  //       if (detourX == null || candidate > detourX) detourX = candidate;
  //     }
  //   }

  //   if (detourX != null) {
  //     return Path()
  //       ..moveTo(start.dx, start.dy)
  //       ..lineTo(detourX, start.dy)
  //       ..lineTo(detourX, yesY)
  //       ..lineTo(end.dx, yesY)
  //       ..lineTo(end.dx, end.dy);
  //   }

  //   return Path()
  //     ..moveTo(start.dx, start.dy)
  //     ..lineTo(start.dx, yesY)
  //     ..lineTo(end.dx, yesY)
  //     ..lineTo(end.dx, end.dy);
  // }

  // double _computeCorridorX(FlowchartGraph g, ConnectionData c) {
  //   final bas = spacing.stepX / 6;
  //   final corridorGap = nodeSize.width / 6;
  //   // final maxDepth = LayoutEngine.maxForDepth(g);
  //   final start = _portPosition(
  //     g.nodes[c.sourceNodeName]!,
  //     c.sourcePort,
  //     outgoing: true,
  //   );

  //   final tgt = g.nodes[c.targetNodeName];
  //   if (tgt == null) return start.dx + bas / 2;

  //   // final targetCenterX = tgt.position.dx + nodeSize.width / 2;

  //   final hasYesToSame = (g.outgoing[c.sourceNodeName] ?? const []).any(
  //     (x) => x.sourcePort == 'yes' && x.targetNodeName == c.targetNodeName,
  //   );

  //   if (hasYesToSame) {
  //     final outer = _noBranchOuterCount(g, c);
  //     final targetRight = tgt.position.dx + nodeSize.width;
  //     return targetRight + corridorGap * (1 + outer);
  //     // return targetCenterX + corridorGap * (1 + outer);
  //   }

  //   // ── Реальный no: как раньше + координация с inner ──
  //   final maxDepth = LayoutEngine.maxForDepth(g);
  //   double? nearestLeftEdge;
  //   for (final e in g.nodes.entries) {
  //     if (e.key == c.sourceNodeName) continue;
  //     if (e.key == c.targetNodeName) continue;
  //     final n = e.value;
  //     if (n.position.dx <= start.dx + 1.0) continue;
  //     double edge = n.position.dx;
  //     if (n.data is ForBlock) {
  //       final ancestors = _forAncestorCount(g, e.key);
  //       final levels = (maxDepth - ancestors).clamp(0, 10);
  //       final inset = bas / 2 * (levels + 1);
  //       if (n.position.dx - inset < edge) edge = n.position.dx - inset;
  //     }
  //     if (nearestLeftEdge == null || edge < nearestLeftEdge) {
  //       nearestLeftEdge = edge;
  //     }
  //   }

  //   double baseX = nearestLeftEdge != null
  //       ? nearestLeftEdge - corridorGap / 2
  //       : start.dx + bas / 2;

  //   final myOuter = _noBranchOuterCount(g, c);
  //   for (final other in g.connections) {
  //     if (other.sourcePort != 'no') continue;
  //     if (other.targetPort == 'loopback') continue;
  //     if (other.targetNodeName != c.targetNodeName) continue;
  //     if (identical(other, c)) continue;
  //     if (_noBranchOuterCount(g, other) >= myOuter) continue;
  //     final innerX = _computeCorridorX(g, other);
  //     if (innerX + corridorGap > baseX) baseX = innerX + corridorGap;
  //   }
  //   return baseX;
  // }

  // Path _routeBody(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) => _routeDefault(start, end, g, c);

  // Set<String> _yesBranchUntilMerge(FlowchartGraph g, String logicName) {
  //   ConnectionData? yesConn, noConn;
  //   for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
  //     if (c.sourcePort == 'yes') yesConn = c;
  //     if (c.sourcePort == 'no') noConn = c;
  //   }
  //   if (yesConn == null || noConn == null) return {};
  //   if (yesConn.targetNodeName == noConn.targetNodeName) return {};

  //   // «Зона слияния» — всё, достижимое из no-ветки.
  //   final noReach = <String>{};
  //   final q1 = <String>[noConn.targetNodeName];
  //   while (q1.isNotEmpty) {
  //     final cur = q1.removeAt(0);
  //     if (!noReach.add(cur)) continue;
  //     if (g.isEnd(cur)) continue;
  //     for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
  //       if (c.targetPort == 'loopback') continue;
  //       q1.add(c.targetNodeName);
  //     }
  //   }

  //   // yes-ветка BFS с остановкой на первой merge-точке.
  //   final result = <String>{};
  //   final q2 = <String>[yesConn.targetNodeName];
  //   while (q2.isNotEmpty) {
  //     final cur = q2.removeAt(0);
  //     if (noReach.contains(cur)) continue;
  //     if (g.isEnd(cur)) continue;
  //     if (!result.add(cur)) continue;
  //     for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
  //       if (c.targetPort == 'loopback') continue;
  //       q2.add(c.targetNodeName);
  //     }
  //   }
  //   return result;
  // }
  //
  /// Множество узлов yes-ветки от логики до первой merge-точки с no-веткой.
  /// Нужен для построения правого коридора обхода (_noCorridorX).
  Set<String> _yesBranchUntilMerge(FlowchartGraph g, String logicName) {
    ConnectionData? yesConn, noConn;
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.sourcePort == 'yes') yesConn = c;
      if (c.sourcePort == 'no') noConn = c;
    }
    if (yesConn == null || noConn == null) return {};
    if (yesConn.targetNodeName == noConn.targetNodeName) return {};

    // «Зона слияния» — всё, достижимое из no-ветки.
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

    // yes-ветка BFS с остановкой на первой merge-точке.
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

  /// «Настоящая» no-ветка: цель левее источника и это не случай
  /// yes+no одного родителя в одну цель (тот обрабатывается отдельно).
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

  /// Слот logic-блока среди «настоящих» no-веток того же столбца, что выше его.
  /// 0 — верхний в столбце; каждый следующий получает +1.
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

    // Обходим всё yes-поддерево (до merge-точки) с учётом своих коридоров детей
    final yesSubtree = _yesBranchUntilMerge(g, logicName);
    for (final childName in yesSubtree) {
      final child = g.nodes[childName];
      if (child == null) continue;

      final blockRight = child.position.dx + nodeSize.width;
      double visualRight = blockRight;

      // For: exit-коридор идёт правее правого края
      if (child.data is ForBlock) {
        final ancestors = _forAncestorCount(g, childName);
        final levels = (maxDepth - ancestors).clamp(0, 10);
        final forCorridor = blockRight + bas / 2 * (levels + 1);
        if (forCorridor > visualRight) visualRight = forCorridor;
      }

      // Logic с «настоящей» no-веткой: рекурсивно берём её коридор.
      // hasYesToSame обрабатывается отдельной схемой — здесь его не учитываем.
      if (child.data is LogicBlock) {
        final hasRealNo = (g.outgoing[childName] ?? const []).any(
          (c) => _isRealNoBranch(g, c),
        );
        if (hasRealNo) {
          final childCorridor = _noCorridorX(g, childName, visiting: visiting);
          if (childCorridor > visualRight) visualRight = childCorridor;
        }
      }

      final need = visualRight + corridorGap;
      if (need > rightX) rightX = need;
    }

    // final myTarget = (g.outgoing[logicName] ?? const <ConnectionData>[])
    //     .firstWhereOrNull((c) => c.sourcePort == 'no');

    // // НОВОЕ: коридор должен быть правее ВСЕХ no-источников к той же цели
    // for (final other in g.connections) {
    //   if (other.sourcePort != 'no') continue;
    //   if (other.targetPort == 'loopback') continue;
    //   if (other.targetNodeName != myTarget?.targetNodeName) continue;
    //   if (!_isRealNoBranch(g, other)) continue;
    //   final src = g.nodes[other.sourceNodeName];
    //   if (src == null) continue;
    //   final r = src.position.dx + nodeSize.width + corridorGap;
    //   if (r > rightX) rightX = r;
    // }

    rightX += bas / 2 * _noBranchSlot(g, logicName);

    visiting.remove(logicName);
    return rightX;
  }

  // Path _routeNo(Offset start, Offset end, FlowchartGraph g, ConnectionData c) {
  //   final path = Path()..moveTo(start.dx, start.dy);
  //   final targetIsLeft = end.dx < start.dx - 1.0;
  //   final bas = spacing.stepX / 6;

  //   final hasYesToSame = (g.outgoing[c.sourceNodeName] ?? const []).any(
  //     (x) => x.sourcePort == 'yes' && x.targetNodeName == c.targetNodeName,
  //   );

  //   if (hasYesToSame) {
  //     return _routeNoWithYesMerge(path, start, end, g, c);
  //   }
  //   // Цель не левее источника
  //   if (!targetIsLeft) {
  //     final hasSiblingNo = g.connections.any(
  //       (o) =>
  //           !identical(o, c) &&
  //           o.sourcePort == 'no' &&
  //           o.targetPort != 'loopback' &&
  //           o.targetNodeName == c.targetNodeName,
  //     );

  //     if (hasSiblingNo) {
  //       final noY = _finalNoY(g, c);
  //       path
  //         ..lineTo(start.dx, noY)
  //         ..lineTo(end.dx, noY)
  //         ..lineTo(end.dx, end.dy);
  //       return path;
  //     }
  //     final targetIsBelow = end.dy >= start.dy + 2.0;
  //     if (targetIsBelow) {
  //       path
  //         ..lineTo(end.dx, start.dy)
  //         ..lineTo(end.dx, end.dy);
  //       return path;
  //     }
  //     final channelY = start.dy + spacing.stepY / 3;
  //     path
  //       ..lineTo(start.dx, channelY)
  //       ..lineTo(end.dx, channelY)
  //       ..lineTo(end.dx, end.dy);
  //     return path;
  //   }

  //   // Цель левее источника: правый коридор с рекурсивным обходом
  //   final rightX = _noCorridorX(g, c.sourceNodeName);

  //   // channelY: ниже всех блоков в полосе [minX, rightX]
  //   final minX = end.dx < start.dx ? end.dx : start.dx;
  //   double maxBottom = start.dy;
  //   for (final e in g.nodes.entries) {
  //     if (e.key == c.targetNodeName) continue;
  //     final n = e.value;
  //     final left = n.position.dx;
  //     final right = left + nodeSize.width;
  //     if (right < minX || left > rightX) continue;
  //     if (n.position.dy >= end.dy - 1.0) continue;
  //     final bottom = n.position.dy + nodeSize.height;
  //     if (bottom > maxBottom) maxBottom = bottom;
  //   }

  //   // ── Цель левее источника ──
  //   // final rightX = _noCorridorX(g, c.sourceNodeName);
  //   final channelY = _finalNoY(g, c);
  //   final endPortY = _portPosition(
  //     g.nodes[c.targetNodeName]!,
  //     'in',
  //     outgoing: false,
  //   ).dy;

  //   path
  //     ..lineTo(rightX, start.dy)
  //     ..lineTo(rightX, channelY)
  //     ..lineTo(end.dx, channelY)
  //     ..lineTo(end.dx, endPortY);
  //   return path;
  // }

  // double get _pairGap => spacing.stepX / 12;

  /// Y середины «прямого» ребра — та же формула, что в _routeDefault,
  /// чтобы yes и его не-пара считались согласованно.
  // double _directMidYFromPorts(
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) {
  //   if ((start.dx - end.dx).abs() < 0.5) return end.dy;
  //   final minX = start.dx < end.dx ? start.dx : end.dx;
  //   final maxX = start.dx < end.dx ? end.dx : start.dx;
  //   double maxBottom = start.dy;
  //   for (final e in g.nodes.entries) {
  //     if (e.key == c.targetNodeName) continue;
  //     final n = e.value;
  //     final left = n.position.dx;
  //     final right = left + nodeSize.width;
  //     if (right < minX || left > maxX) continue;
  //     if (n.position.dy >= end.dy - 1.0) continue;
  //     final bottom = n.position.dy + nodeSize.height;
  //     if (bottom <= start.dy) continue;
  //     if (bottom > maxBottom) maxBottom = bottom;
  //   }
  //   final desired = maxBottom + spacing.stepY / 2;
  //   final cap = end.dy - spacing.stepY / 8;
  //   return desired < cap ? desired : cap;
  // }

  // double _outerMetric(FlowchartGraph g, ConnectionData c) {
  //   final src = g.nodes[c.sourceNodeName];
  //   final tgt = g.nodes[c.targetNodeName];
  //   if (src == null || tgt == null) return 0;
  //   final dxDist = (src.position.dx - tgt.position.dx).abs();
  //   // return dxDist * 1000 + (1000000 - src.position.dy);

  //   if (dxDist < 0.5) return 1e12 + (1000000 - src.position.dy);

  //   return dxDist * 1000 + (1000000 - src.position.dy);
  // }

  // int _noBranchOuterCount(FlowchartGraph g, ConnectionData c) {
  //   final myMetric = _outerMetric(g, c);
  //   int count = 0;
  //   for (final other in g.connections) {
  //     if (identical(other, c)) continue;
  //     if (other.sourcePort != 'no') continue;
  //     if (other.targetPort == 'loopback') continue;
  //     if (other.targetNodeName != c.targetNodeName) continue;
  //     if (_outerMetric(g, other) < myMetric - 0.5) count++;
  //   }
  //   return count;
  // }

  // int _maxNoBranchOuterCount(FlowchartGraph g, String target) {
  //   int maxC = 0;
  //   for (final c in g.connections) {
  //     if (c.sourcePort != 'no') continue;
  //     if (c.targetPort == 'loopback') continue;
  //     if (c.targetNodeName != target) continue;
  //     final cnt = _noBranchOuterCount(g, c);
  //     if (cnt > maxC) maxC = cnt;
  //   }
  //   return maxC;
  // }

  // Path _routeNoWithYesMerge(
  //   Path path,
  //   Offset start,
  //   Offset end,
  //   FlowchartGraph g,
  //   ConnectionData c,
  // ) {
  //   final noY = _finalNoY(g, c);
  //   final yesY = noY - _pairGapValue();

  //   debugPrint(
  //     '[no-with-yes] ${c.sourceNodeName}→${c.targetNodeName} '
  //     'yesY=${yesY.toStringAsFixed(1)} '
  //     'noY=${noY.toStringAsFixed(1)} '
  //     'outer=${_noBranchOuterCount(g, c)}',
  //   );
  //   path
  //     ..lineTo(start.dx, noY)
  //     ..lineTo(end.dx, noY)
  //     ..lineTo(end.dx, end.dy);
  //   return path;
  // }

  // exit: из правого порта For, обходим тело цикла справа и снизу
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

    // Цель правее правого края - обходить нечего
    if (end.dx >= rightX) {
      return RoutedConnection(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, start.dy)
          ..lineTo(end.dx, end.dy),
        [ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2)],
      );
    }

    return RoutedConnection(
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(rightX, start.dy)
        ..lineTo(rightX, turnY)
        ..lineTo(end.dx, turnY)
        ..lineTo(end.dx, end.dy),
      [ArrowMarker(Offset(end.dx, end.dy - spacing.stepY / 8), math.pi / 2)],
    );
  }

  // loopback: из низа тела цикла -> влево -> вверх -> в левый порт For
  RoutedConnection _routeLoopback(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final bas = spacing.stepX / 6;

    final ancestors = _forAncestorCount(g, c.targetNodeName);
    final maxDepth = LayoutEngine.maxForDepth(g);
    final levelsFromInner = maxDepth - ancestors; // 0 у самого внутреннего
    final inset = bas / 2 * (levelsFromInner + 1);
    // final gap = spacing.stepX / 6;
    return RoutedConnection(
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, start.dy + bas / 3)
        ..lineTo(end.dx - inset, start.dy + bas / 3)
        ..lineTo(end.dx - inset, end.dy)
        ..lineTo(end.dx, end.dy),
      [ArrowMarker(Offset(end.dx, end.dy), 0.0)],
    );
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

      // Габарит по X: правый край + коридор исходящей no-ветки.
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
