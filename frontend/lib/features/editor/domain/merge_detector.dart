import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';

/// Событие слияния двух ветвей на общей горизонтальной шине.
///
/// Семантика (см. И1–И5):
/// - Все не-loopback, не-exit связи в один target используют один [busY].
/// - Для каждой горизонтали (dropX ≠ endX) детектор ищет **первую**
///   в направлении потока чужую вертикаль, пересекающую `busY`. Это [xMerge].
/// - Если такой вертикали нет, но в target есть прямая вертикаль (yes),
///   слияние происходит на `endX` (T-стык): горизонталь вливается в вертикаль.
/// - Одна горизонталь = одно событие = одна стрелка по варианту C
///   (за `arrowInset` **до** точки слияния в направлении потока).
class MergeEvent {
  final String targetName;
  final double busY;

  /// X, где чужая ветвь вливается в нашу горизонталь.
  final double xMerge;

  /// X, куда течёт наша горизонталь.
  final double xEnd;

  /// Направление потока: `true` — справа налево.
  final bool flowLeft;

  /// Связь, чья вертикаль создаёт слияние.
  final ConnectionData joiningConn;

  /// Наша связь — та, чья горизонталь проходит через слияние.
  final ConnectionData ourConn;

  const MergeEvent({
    required this.targetName,
    required this.busY,
    required this.xMerge,
    required this.xEnd,
    required this.flowLeft,
    required this.joiningConn,
    required this.ourConn,
  });

  /// Позиция стрелки (вариант C): на нашей горизонтали, за [arrowInset]
  /// **до** [xMerge] в направлении потока.
  Offset arrowPosition(double arrowInset) {
    final x = flowLeft ? xMerge + arrowInset : xMerge - arrowInset;
    return Offset(x, busY);
  }

  double arrowAngle() => flowLeft ? math.pi : 0.0;

  @override
  String toString() =>
      '[merge] $targetName busY=${busY.toStringAsFixed(1)} '
      'xMerge=${xMerge.toStringAsFixed(1)} '
      'flowLeft=$flowLeft '
      'from=${ourConn.sourceNodeName}.${ourConn.sourcePort}';
}

/// Единственная точка правды о «где сливаются ветви».
///
/// Заменяет:
/// - `ConnectionRouter._busArrows`-эвристику «поиска чужой вертикали»
///   через `_otherVerticalSpan` / `_dropXOf`;
/// - `InsertionPointsService._computeMergeInfo`-эвристику «landingY по
///   сэмплам пути» с шагом 1.0.
///
/// Оба раньше вычисляли «где merge» независимо, и результаты расходились
/// на 1–2 px, из-за чего плюс «после слияния» и стрелка «на слиянии»
/// вставали в разные точки.
class MergeDetector {
  final ConnectionRouter router;

  FlowchartGraph? _cachedGraph;
  List<MergeEvent>? _cached;

  MergeDetector({required this.router});

  void resetCache() {
    _cachedGraph = null;
    _cached = null;
  }

  /// Все события слияния в графе.
  List<MergeEvent> detect(FlowchartGraph g) {
    if (identical(_cachedGraph, g) && _cached != null) return _cached!;
    _cachedGraph = g;
    final result = <MergeEvent>[];

    final byTarget = <String, List<ConnectionData>>{};
    for (final c in g.connections) {
      if (c.targetPort == 'loopback') continue;
      if (c.sourcePort == 'exit') continue;
      byTarget.putIfAbsent(c.targetNodeName, () => []).add(c);
    }

    for (final entry in byTarget.entries) {
      if (entry.value.length < 2) continue;
      result.addAll(_forTarget(g, entry.key, entry.value));
    }

    _cached = result;
    return result;
  }

  /// События слияния, участником которых является [c] как `ourConn`.
  List<MergeEvent> forConnection(FlowchartGraph g, ConnectionData c) {
    return detect(
      g,
    ).where((e) => identical(e.ourConn, c)).toList(growable: false);
  }

  List<MergeEvent> _forTarget(
    FlowchartGraph g,
    String targetName,
    List<ConnectionData> conns,
  ) {
    final tgt = g.nodes[targetName];
    if (tgt == null) return const [];

    final busY = router.debugBusY(g, targetName);
    if (busY <= 0) return const []; // все связи вертикальные, шины нет

    final endX = tgt.position.dx + router.nodeSize.width / 2;

    // dropX каждой связи на busY
    final drops = <_Drop>[];
    for (final c in conns) {
      final src = g.nodes[c.sourceNodeName];
      if (src == null) continue;
      drops.add(_Drop(c, router.debugDropX(g, c)));
    }
    if (drops.length < 2) return const [];

    // Прямые вертикали (dropX == endX) — yes-подобные связи.
    final hasVertical = drops.any((d) => (d.x - endX).abs() < 0.5);
    final horizontals = drops
        .where((d) => (d.x - endX).abs() >= 0.5)
        .toList(growable: false);

    if (horizontals.isEmpty) return const [];

    final events = <MergeEvent>[];

    for (final our in horizontals) {
      final flowLeft = our.x > endX;
      _Drop? nearestDrop;
      double? nearestX;

      for (final other in horizontals) {
        if (identical(other, our)) continue;
        if (flowLeft) {
          if (other.x <= endX + 0.5) continue;
          if (other.x >= our.x - 0.5) continue;
          if (nearestX == null || other.x > nearestX) {
            nearestX = other.x;
            nearestDrop = other;
          }
        } else {
          if (other.x <= our.x + 0.5) continue;
          if (other.x >= endX - 0.5) continue;
          if (nearestX == null || other.x < nearestX) {
            nearestX = other.x;
            nearestDrop = other;
          }
        }
      }

      if (nearestDrop != null) {
        // Промежуточное слияние с другой горизонталью
        events.add(
          MergeEvent(
            targetName: targetName,
            busY: busY,
            xMerge: nearestX!,
            xEnd: endX,
            flowLeft: flowLeft,
            joiningConn: nearestDrop.conn,
            ourConn: our.conn,
          ),
        );
      } else if (hasVertical) {
        // T-стык в прямую вертикаль (yes) на endX
        final vertical = drops.firstWhere((d) => (d.x - endX).abs() < 0.5);
        events.add(
          MergeEvent(
            targetName: targetName,
            busY: busY,
            xMerge: endX,
            xEnd: endX,
            flowLeft: flowLeft,
            joiningConn: vertical.conn,
            ourConn: our.conn,
          ),
        );
      }
      // иначе: единственная горизонталь без вертикали — слияния нет
    }

    return events;
  }
}

class _Drop {
  final ConnectionData conn;
  final double x;
  const _Drop(this.conn, this.x);
}
