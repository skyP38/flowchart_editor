import 'dart:math' as math;

// import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import 'connection_router.dart';
import 'flowchart_graph.dart';

class InsertionPointsService {
  final ConnectionRouter router;
  const InsertionPointsService({required this.router});

  List<InsertionPoint> compute(FlowchartGraph g) {
    final points = <InsertionPoint>[];

    // 1. Все target с ≥2 входящими non-loopback.
    final incomingByTarget = <String, List<ConnectionData>>{};
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      incomingByTarget.putIfAbsent(conn.targetNodeName, () => []).add(conn);
    }

    // 2. Для каждого merge-target вычисляем точку слияния.
    final mergeInfoByTarget = <String, _MergeInfo>{};
    for (final e in incomingByTarget.entries) {
      if (e.value.length < 2) continue;
      final target = g.nodes[e.key];
      if (target == null) continue;
      final info = _computeMergeInfo(g, e.value, target);
      if (info != null) mergeInfoByTarget[e.key] = info;
    }

    // 3. Для каждой связи:
    //    - если target — merge: "before" (на этой ветке до mergeY);
    //    - иначе: обычный плюс (середина/специфика ветки).
    for (final conn in g.connections) {
      if (conn.targetPort == 'loopback') continue;
      final path = router.build(conn, g);
      if (path.computeMetrics().isEmpty) continue;

      final mergeInfo = mergeInfoByTarget[conn.targetNodeName];
      if (mergeInfo != null) {
        final before = _midpointBefore(path, mergeInfo.mergeY);
        if (before != null) points.add(InsertionPoint(before, conn));
        continue;
      }

      Offset? plusPos;
      if (conn.sourcePort == 'no') {
        plusPos = _firstVerticalMidpoint(path);
      } else if (conn.sourcePort == 'exit') {
        final src = g.nodes[conn.sourceNodeName];
        final centerX = src != null
            ? src.position.dx + router.nodeSize.width / 2
            : null;
        plusPos =
            _exitPlusPositionAtX(path, centerX) ??
            _endOfHorizontalSegment(path);
      }
      plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
      if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
    }

    // 4. Для каждого merge-target — ровно один "after".
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

  //  Merge-информация
  _MergeInfo? _computeMergeInfo(
    FlowchartGraph g,
    List<ConnectionData> incoming,
    NodeModel target,
  ) {
    final centerX = target.position.dx + router.nodeSize.width / 2;
    final targetTop = target.position.dy;

    double? maxLandingY;
    ConnectionData? deepestEdge;
    for (final conn in incoming) {
      final path = router.build(conn, g);
      if (path.computeMetrics().isEmpty) continue;
      final y = _landingYAt(path, centerX, targetTop);
      if (y != null && (maxLandingY == null || y > maxLandingY)) {
        maxLandingY = y;
        deepestEdge = conn;
      }
    }
    if (maxLandingY == null || deepestEdge == null) return null;

    // Небольшой запас, чтобы "+" не наезжал на контур блока
    final gap = targetTop - maxLandingY;
    if (gap < 5) return null;

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

  //  точка на ветке до Y слияния
  Offset? _midpointBefore(Path path, double y) {
    final samples = _samplePath(path).where((p) => p.dy < y - 0.5).toList();
    if (samples.isEmpty) return null;
    return samples[samples.length ~/ 2];
  }

  //  exit
  Offset? _exitPlusPositionAtX(Path path, double? targetX) {
    if (targetX == null) return null;
    final segs = _extractSegments(path);
    if (segs.isEmpty) return null;

    _Seg? lastHorz;
    for (final s in segs) {
      final isHorz =
          (s.start.dy - s.end.dy).abs() < 0.5 &&
          (s.start.dx - s.end.dx).abs() > 0.5;
      if (isHorz) lastHorz = s;
    }
    if (lastHorz == null) return null;

    final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
    final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);
    if (targetX < xLeft - 0.5 || targetX > xRight + 0.5) return null;

    return Offset(targetX, lastHorz.start.dy);
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

//
// import 'dart:math' as math;

// import 'package:collection/collection.dart';
// import 'package:flutter/material.dart';

// import '../models/editor_models.dart';
// import 'connection_router.dart';
// import 'flowchart_graph.dart';

// class InsertionPointsService {
//   final ConnectionRouter router;
//   const InsertionPointsService({required this.router});

//   List<InsertionPoint> compute(FlowchartGraph g) {
//     final points = <InsertionPoint>[];
//     final handledMergeTargets = <String>{};

//     // 1. Старое поведение: yes/no одного Logic в общий target.
//     for (final conn in g.connections) {
//       if (conn.targetPort == 'loopback') continue;
//       final path = router.build(conn, g);
//       if (path.computeMetrics().isEmpty) continue;

//       if (conn.sourcePort == 'yes') {
//         final noConn = (g.outgoing[conn.sourceNodeName] ?? const [])
//             .firstWhereOrNull(
//               (c) =>
//                   c.sourcePort == 'no' &&
//                   c.targetNodeName == conn.targetNodeName,
//             );
//         if (noConn != null) {
//           final noPath = router.build(noConn, g);
//           final mergeY = _findYesNoMergeY(path, noPath);
//           if (mergeY != null) {
//             final before = _midpointOnYesBefore(path, mergeY);
//             final after = _midpointOnYesAfter(path, mergeY);
//             if (before != null) points.add(InsertionPoint(before, conn));
//             if (after != null) {
//               final otherIds = <String>[];
//               for (final c in g.connections) {
//                 if (c.targetPort == 'loopback') continue;
//                 if (c.targetNodeName != conn.targetNodeName) continue;
//                 if (identical(c, conn)) continue;
//                 if (c.id == null) continue;
//                 otherIds.add(c.id!);
//               }
//               points.add(
//                 InsertionPoint(
//                   after,
//                   conn,
//                   isAfterMerge: true,
//                   mergeOtherConnIds: otherIds,
//                   // mergeOtherConnIds: noConn.id == null
//                   // ? const []
//                   // : [noConn.id!],
//                 ),
//               );
//             }
//             handledMergeTargets.add(conn.targetNodeName);
//             continue;
//           }
//         }
//       }

//       Offset? plusPos;
//       if (conn.sourcePort == 'no') {
//         plusPos = _firstVerticalMidpoint(path);
//       } else if (conn.sourcePort == 'exit') {
//         final src = g.nodes[conn.sourceNodeName];
//         final centerX = src != null
//             ? src.position.dx + router.nodeSize.width / 2
//             : null;
//         plusPos =
//             _exitPlusPositionAtX(path, centerX) ??
//             _endOfHorizontalSegment(path);
//       }
//       plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
//       if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
//     }

//     // 2. Обобщённые слияния: любой target с ≥2 входящими.
//     final incomingByTarget = <String, List<ConnectionData>>{};
//     for (final conn in g.connections) {
//       if (conn.targetPort == 'loopback') continue;
//       incomingByTarget.putIfAbsent(conn.targetNodeName, () => []).add(conn);
//     }

//     for (final e in incomingByTarget.entries) {
//       if (e.value.length < 2) continue;
//       if (handledMergeTargets.contains(e.key)) continue;
//       final target = g.nodes[e.key];
//       if (target == null) continue;

//       final centerX = target.position.dx + router.nodeSize.width / 2;
//       final targetTop = target.position.dy;

//       double? maxLandingY;
//       ConnectionData? deepestEdge;
//       for (final conn in e.value) {
//         final path = router.build(conn, g);
//         if (path.computeMetrics().isEmpty) continue;
//         final y = _landingYAt(path, centerX, targetTop);
//         if (y != null && (maxLandingY == null || y > maxLandingY)) {
//           maxLandingY = y;
//           deepestEdge = conn;
//         }
//       }
//       if (maxLandingY == null || deepestEdge == null) continue;

//       final gap = targetTop - maxLandingY;
//       if (gap < 20) continue;

//       final otherConnIds = e.value
//           .where((c) => c.id != null && c.id != deepestEdge!.id)
//           .map((c) => c.id!)
//           .toList();

//       points.add(
//         InsertionPoint(
//           Offset(centerX, (maxLandingY + targetTop) / 2),
//           deepestEdge,
//           isAfterMerge: true,
//           mergeOtherConnIds: otherConnIds,
//         ),
//       );
//       handledMergeTargets.add(e.key);
//     }

//     return points;
//   }

//   // --- yes/no одного Logic -----------------------------------------------

//   double? _findYesNoMergeY(Path yesPath, Path noPath) {
//     final yesSamples = _samplePath(yesPath);
//     final noSegments = _extractSegments(noPath);

//     _Seg? lastHorz;
//     for (final s in noSegments) {
//       final isHorz =
//           (s.start.dy - s.end.dy).abs() < 0.5 &&
//           (s.start.dx - s.end.dx).abs() > 0.5;
//       if (isHorz) lastHorz = s;
//     }
//     if (lastHorz == null) return null;

//     final y = lastHorz.start.dy;
//     final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
//     final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);

//     for (final p in yesSamples) {
//       if ((p.dy - y).abs() < 0.5 &&
//           p.dx >= xLeft - 0.5 &&
//           p.dx <= xRight + 0.5) {
//         return y;
//       }
//     }
//     return null;
//   }

//   Offset? _midpointOnYesBefore(Path path, double mergeY) {
//     final s = _samplePath(path).where((p) => p.dy < mergeY - 0.5).toList();
//     if (s.length < 2) return null;
//     return Offset(s.first.dx, (s.first.dy + s.last.dy) / 2);
//   }

//   Offset? _midpointOnYesAfter(Path path, double mergeY) {
//     final s = _samplePath(path).where((p) => p.dy > mergeY + 0.5).toList();
//     if (s.length < 2) return null;
//     return Offset(s.first.dx, (s.first.dy + s.last.dy) / 2);
//   }

//   // --- Обобщённое слияние -------------------------------------------------

//   double? _landingYAt(Path path, double centerX, double targetTop) {
//     final samples = _samplePath(path);
//     double? best;
//     for (final p in samples) {
//       if ((p.dx - centerX).abs() > 1.0) continue;
//       if (p.dy >= targetTop - 1.0) continue;
//       if (best == null || p.dy < best) best = p.dy;
//     }
//     return best;
//   }

//   // --- exit ---------------------------------------------------------------

//   Offset? _exitPlusPositionAtX(Path path, double? targetX) {
//     if (targetX == null) return null;
//     final segs = _extractSegments(path);
//     if (segs.isEmpty) return null;

//     _Seg? lastHorz;
//     for (final s in segs) {
//       final isHorz =
//           (s.start.dy - s.end.dy).abs() < 0.5 &&
//           (s.start.dx - s.end.dx).abs() > 0.5;
//       if (isHorz) lastHorz = s;
//     }
//     if (lastHorz == null) return null;

//     final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
//     final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);
//     if (targetX < xLeft - 0.5 || targetX > xRight + 0.5) return null;

//     return Offset(targetX, lastHorz.start.dy);
//   }

//   // --- Общие хелперы ------------------------------------------------------

//   List<Offset> _samplePath(Path path) {
//     final out = <Offset>[];
//     for (final metric in path.computeMetrics()) {
//       for (double d = 0; d <= metric.length; d += 1) {
//         final t = metric.getTangentForOffset(d);
//         if (t != null) out.add(t.position);
//       }
//     }
//     return out;
//   }

//   List<_Seg> _extractSegments(Path path) {
//     final samples = _samplePath(path);
//     final segs = <_Seg>[];
//     if (samples.length < 2) return segs;

//     _Seg cur = _Seg(samples[0], samples[0]);
//     for (int i = 1; i < samples.length; i++) {
//       final a = samples[i - 1], b = samples[i];
//       final sameX = (a.dx - b.dx).abs() < 0.5;
//       final sameY = (a.dy - b.dy).abs() < 0.5;
//       final isHorz = sameY && !sameX;
//       final isVert = sameX && !sameY;
//       final curHorz =
//           (cur.start.dy - cur.end.dy).abs() < 0.5 &&
//           (cur.start.dx - cur.end.dx).abs() > 0.5;
//       final curVert =
//           (cur.start.dx - cur.end.dx).abs() < 0.5 &&
//           (cur.start.dy - cur.end.dy).abs() > 0.5;
//       if ((curHorz && isHorz) || (curVert && isVert) || cur.start == cur.end) {
//         cur = _Seg(cur.start, b);
//       } else {
//         if (cur.start != cur.end) segs.add(cur);
//         cur = _Seg(a, b);
//       }
//     }
//     if (cur.start != cur.end) segs.add(cur);
//     return segs;
//   }

//   Offset? _midOfPath(Path path) {
//     for (final metric in path.computeMetrics()) {
//       if (metric.length <= 0.1) continue;
//       final t = metric.getTangentForOffset(metric.length / 2);
//       if (t != null) return t.position;
//     }
//     return null;
//   }

//   Offset? _firstVerticalMidpoint(Path path) {
//     final samples = _samplePath(path);
//     if (samples.length < 2) return null;

//     for (int i = 1; i < samples.length; i++) {
//       final a = samples[i - 1];
//       final b = samples[i];
//       final isVertical = (a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() > 0.5;
//       if (!isVertical) continue;

//       int endIdx = i;
//       while (endIdx < samples.length - 1) {
//         final p = samples[endIdx];
//         final q = samples[endIdx + 1];
//         final stillVertical =
//             (p.dx - q.dx).abs() < 0.5 && (p.dy - q.dy).abs() > 0.5;
//         if (!stillVertical) break;
//         endIdx++;
//       }
//       final top = samples[i - 1];
//       final bottom = samples[endIdx];
//       return Offset(top.dx, (top.dy + bottom.dy) / 2);
//     }
//     return null;
//   }

//   Offset? _endOfHorizontalSegment(Path path) {
//     Offset? lastCorner;
//     for (final metric in path.computeMetrics()) {
//       bool wasHorizontal = false;
//       for (double d = 0; d <= metric.length; d += 1) {
//         final t = metric.getTangentForOffset(d);
//         if (t == null) continue;
//         final v = t.vector;
//         final isVert = v.dx.abs() < 0.5 && v.dy.abs() > 0.5;
//         final isHorz = v.dx.abs() > 0.5 && v.dy.abs() < 0.5;
//         if (isHorz) {
//           wasHorizontal = true;
//         } else if (isVert && wasHorizontal) {
//           lastCorner = t.position;
//           wasHorizontal = false;
//         }
//       }
//     }
//     return lastCorner;
//   }
// }

// class _Seg {
//   final Offset start;
//   final Offset end;
//   const _Seg(this.start, this.end);
// }
// // import 'package:flutter/material.dart';
// // import '../models/editor_models.dart';
// // import 'connection_router.dart';
// // import 'flowchart_graph.dart';
// // import 'dart:math' as math;

// // class InsertionPointsService {
// //   final ConnectionRouter router;
// //   const InsertionPointsService({required this.router});

// //   List<InsertionPoint> compute(FlowchartGraph g) {
// //     final points = <InsertionPoint>[];
// //     final handledMergeTargets = <String>{};

// //     // 1. Старое поведение: yes/no одного Logic в общий target.
// //     for (final conn in g.connections) {
// //       if (conn.targetPort == 'loopback') continue;
// //       final path = router.build(conn, g);
// //       if (path.computeMetrics().isEmpty) continue;

// //       if (conn.sourcePort == 'yes') {
// //         final noConn = (g.outgoing[conn.sourceNodeName] ?? const [])
// //             .firstWhereOrNull(
// //               (c) =>
// //                   c.sourcePort == 'no' &&
// //                   c.targetNodeName == conn.targetNodeName,
// //             );
// //         if (noConn != null) {
// //           final noPath = router.build(noConn, g);
// //           final mergeY = _findYesNoMergeY(path, noPath);
// //           if (mergeY != null) {
// //             final before = _midpointOnYesBefore(path, mergeY);
// //             final after = _midpointOnYesAfter(path, mergeY);
// //             if (before != null) points.add(InsertionPoint(before, conn));
// //             if (after != null) {
// //               points.add(
// //                 InsertionPoint(
// //                   after,
// //                   conn,
// //                   isAfterMerge: true,
// //                   mergeOtherConnIds: noConn.id == null
// //                       ? const []
// //                       : [noConn.id!],
// //                 ),
// //               );
// //             }
// //             handledMergeTargets.add(conn.targetNodeName);
// //             continue;
// //           }
// //         }
// //       }

// //       Offset? plusPos;
// //       if (conn.sourcePort == 'no') {
// //         plusPos = _firstVerticalMidpoint(path);
// //       } else if (conn.sourcePort == 'exit') {
// //         final src = g.nodes[conn.sourceNodeName];
// //         final centerX = src != null
// //             ? src.position.dx + router.nodeSize.width / 2
// //             : null;
// //         plusPos =
// //             _exitPlusPositionAtX(path, centerX) ??
// //             _endOfHorizontalSegment(path);
// //       }
// //       plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
// //       if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
// //     }

// //     // 2. Обобщённые слияния: любой target с ≥2 входящими.
// //     final incomingByTarget = <String, List<ConnectionData>>{};
// //     for (final conn in g.connections) {
// //       if (conn.targetPort == 'loopback') continue;
// //       incomingByTarget.putIfAbsent(conn.targetNodeName, () => []).add(conn);
// //     }

// //     for (final e in incomingByTarget.entries) {
// //       if (e.value.length < 2) continue;
// //       if (handledMergeTargets.contains(e.key)) continue;
// //       final target = g.nodes[e.key];
// //       if (target == null) continue;

// //       final centerX = target.position.dx + router.nodeSize.width / 2;
// //       final targetTop = target.position.dy;

// //       double? maxLandingY;
// //       ConnectionData? deepestEdge;
// //       for (final conn in e.value) {
// //         final path = router.build(conn, g);
// //         if (path.computeMetrics().isEmpty) continue;
// //         final y = _landingYAt(path, centerX, targetTop);
// //         if (y != null && (maxLandingY == null || y > maxLandingY)) {
// //           maxLandingY = y;
// //           deepestEdge = conn;
// //         }
// //       }
// //       if (maxLandingY == null || deepestEdge == null) continue;

// //       final gap = targetTop - maxLandingY;
// //       if (gap < 20) continue;

// //       final otherConnIds = e.value
// //           .where((c) => c.id != deepestEdge!.id && c.id != null)
// //           .map((c) => c.id!)
// //           .toList();

// //       points.add(
// //         InsertionPoint(
// //           Offset(centerX, (maxLandingY + targetTop) / 2),
// //           deepestEdge,
// //           isAfterMerge: true,
// //           mergeOtherConnIds: otherConnIds,
// //         ),
// //       );
// //       handledMergeTargets.add(e.key);
// //     }

// //     return points;
// //   }

// //   /// Самая высокая точка пути, где x ≈ centerX (перед targetTop).
// //   double? _landingYAt(Path path, double centerX, double targetTop) {
// //     final samples = _samplePath(path);
// //     double? best;
// //     for (final p in samples) {
// //       if ((p.dx - centerX).abs() > 1.0) continue;
// //       if (p.dy >= targetTop - 1.0) continue;
// //       if (best == null || p.dy < best) best = p.dy;
// //     }
// //     return best;
// //   }

// //   double? _findYesNoMergeY(Path yesPath, Path noPath) {
// //     final yesSamples = _samplePath(yesPath);
// //     final noSegments = _extractSegments(noPath);

// //     _Seg? lastHorz;
// //     for (final s in noSegments) {
// //       final isHorz =
// //           (s.start.dy - s.end.dy).abs() < 0.5 &&
// //           (s.start.dx - s.end.dx).abs() > 0.5;
// //       if (isHorz) lastHorz = s;
// //     }
// //     if (lastHorz == null) return null;

// //     final y = lastHorz.start.dy;
// //     final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
// //     final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);

// //     for (final p in yesSamples) {
// //       if ((p.dy - y).abs() < 0.5 &&
// //           p.dx >= xLeft - 0.5 &&
// //           p.dx <= xRight + 0.5) {
// //         return y;
// //       }
// //     }
// //     return null;
// //   }

// //   Offset? _midpointOnYesBefore(Path path, double mergeY) {
// //     final s = _samplePath(path).where((p) => p.dy < mergeY - 0.5).toList();
// //     if (s.length < 2) return null;
// //     return Offset(s.first.dx, (s.first.dy + s.last.dy) / 2);
// //   }

// //   Offset? _midpointOnYesAfter(Path path, double mergeY) {
// //     final s = _samplePath(path).where((p) => p.dy > mergeY + 0.5).toList();
// //     if (s.length < 2) return null;
// //     return Offset(s.first.dx, (s.first.dy + s.last.dy) / 2);
// //   }

// //   Offset? _exitPlusPositionAtX(Path path, double? targetX) {
// //     if (targetX == null) return null;
// //     final segs = _extractSegments(path);
// //     if (segs.isEmpty) return null;

// //     _Seg? lastHorz;
// //     for (final s in segs) {
// //       final isHorz =
// //           (s.start.dy - s.end.dy).abs() < 0.5 &&
// //           (s.start.dx - s.end.dx).abs() > 0.5;
// //       if (isHorz) lastHorz = s;
// //     }
// //     if (lastHorz == null) return null;

// //     final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
// //     final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);
// //     if (targetX < xLeft - 0.5 || targetX > xRight + 0.5) return null;

// //     return Offset(targetX, lastHorz.start.dy);
// //   }

// //   // List<InsertionPoint> compute(FlowchartGraph g) {
// //   //   // Шаг 1: для каждого target собираем точки вливания no-путей
// //   //   // (по последнему горизонтальному сегменту пути)
// //   //   final noMergesByTarget = <String, List<_MergePoint>>{};
// //   //   for (final conn in g.connections) {
// //   //     if (conn.sourcePort != 'no') continue;
// //   //     if (conn.id == null) continue;
// //   //     final path = router.build(conn, g);
// //   //     final mergeY = _lastHorizontalY(path);
// //   //     if (mergeY != null) {
// //   //       noMergesByTarget
// //   //           .putIfAbsent(conn.targetNodeName, () => [])
// //   //           .add(_MergePoint(y: mergeY, connId: conn.id!));
// //   //     }
// //   //   }

// //   //   // Шаг 2: обрабатываем каждую связь
// //   //   final points = <InsertionPoint>[];
// //   //   for (final conn in g.connections) {
// //   //     if (conn.targetPort == 'loopback') continue;
// //   //     final path = router.build(conn, g);
// //   //     if (path.computeMetrics().isEmpty) continue;

// //   //     // yes/out с вливанием no-пути -> разбиваем на до/после слияния
// //   //     _MergePoint? mergeOnPath;
// //   //     if (conn.sourcePort == 'yes' || conn.sourcePort == 'out') {
// //   //       final merges = noMergesByTarget[conn.targetNodeName];
// //   //       if (merges != null) {
// //   //         final samples = _samplePath(path);
// //   //         _MergePoint? best;
// //   //         for (final m in merges) {
// //   //           final onPath = samples.any((p) => (p.dy - m.y).abs() < 1.0);
// //   //           if (onPath && (best == null || m.y > best.y)) best = m;
// //   //         }
// //   //         mergeOnPath = best;
// //   //       }
// //   //     }

// //   //     if (mergeOnPath != null) {
// //   //       final before = _midpointBeforeY(path, mergeOnPath.y);
// //   //       final after = _midpointAfterY(path, mergeOnPath.y);
// //   //       if (before != null) points.add(InsertionPoint(before, conn));
// //   //       if (after != null) {
// //   //         points.add(
// //   //           InsertionPoint(
// //   //             after,
// //   //             conn,
// //   //             isAfterMerge: true,
// //   //             mergeOtherConnId: mergeOnPath.connId,
// //   //           ),
// //   //         );
// //   //       }
// //   //       continue;
// //   //     }

// //   //     Offset? plusPos;
// //   //     if (conn.sourcePort == 'no') {
// //   //       plusPos = _firstVerticalMidpoint(path);
// //   //     } else if (conn.sourcePort == 'exit') {
// //   //       final src = g.nodes[conn.sourceNodeName];
// //   //       final forCenterX = src != null
// //   //           ? src.position.dx + router.nodeSize.width / 2
// //   //           : null;
// //   //       plusPos =
// //   //           _exitPlusPositionAtX(path, forCenterX) ??
// //   //           _endOfHorizontalSegment(path);
// //   //       // plusPos = _endOfHorizontalSegment(path);
// //   //     }
// //   //     plusPos ??= _firstVerticalMidpoint(path) ?? _midOfPath(path);
// //   //     if (plusPos != null) points.add(InsertionPoint(plusPos, conn));
// //   //   }
// //   //   return points;
// //   // }

// //   double? _lastHorizontalY(Path path) {
// //     final segs = _extractSegments(path);
// //     for (final s in segs.reversed) {
// //       final isHorz =
// //           (s.start.dy - s.end.dy).abs() < 0.5 &&
// //           (s.start.dx - s.end.dx).abs() > 0.5;
// //       if (isHorz) return s.start.dy;
// //     }
// //     return null;
// //   }

// //   Offset? _midpointBeforeY(Path path, double y) {
// //     final s = _samplePath(path).where((p) => p.dy < y - 0.5).toList();
// //     if (s.isEmpty) return null;
// //     return s[s.length ~/ 2];
// //   }

// //   Offset? _midpointAfterY(Path path, double y) {
// //     final s = _samplePath(path).where((p) => p.dy > y + 0.5).toList();
// //     if (s.isEmpty) return null;
// //     return s[s.length ~/ 2];
// //   }

// //   List<Offset> _samplePath(Path path) {
// //     final out = <Offset>[];
// //     for (final metric in path.computeMetrics()) {
// //       for (double d = 0; d <= metric.length; d += 1) {
// //         final t = metric.getTangentForOffset(d);
// //         if (t != null) out.add(t.position);
// //       }
// //     }
// //     return out;
// //   }

// //   List<_Seg> _extractSegments(Path path) {
// //     final samples = _samplePath(path);
// //     final segs = <_Seg>[];
// //     if (samples.length < 2) return segs;

// //     _Seg cur = _Seg(samples[0], samples[0]);
// //     for (int i = 1; i < samples.length; i++) {
// //       final a = samples[i - 1], b = samples[i];
// //       final sameX = (a.dx - b.dx).abs() < 0.5;
// //       final sameY = (a.dy - b.dy).abs() < 0.5;
// //       final isHorz = sameY && !sameX;
// //       final isVert = sameX && !sameY;
// //       final curHorz =
// //           (cur.start.dy - cur.end.dy).abs() < 0.5 &&
// //           (cur.start.dx - cur.end.dx).abs() > 0.5;
// //       final curVert =
// //           (cur.start.dx - cur.end.dx).abs() < 0.5 &&
// //           (cur.start.dy - cur.end.dy).abs() > 0.5;
// //       if ((curHorz && isHorz) || (curVert && isVert) || cur.start == cur.end) {
// //         cur = _Seg(cur.start, b);
// //       } else {
// //         if (cur.start != cur.end) segs.add(cur);
// //         cur = _Seg(a, b);
// //       }
// //     }
// //     if (cur.start != cur.end) segs.add(cur);
// //     return segs;
// //   }

// //   Offset? _midOfPath(Path path) {
// //     for (final metric in path.computeMetrics()) {
// //       if (metric.length <= 0.1) continue;
// //       final t = metric.getTangentForOffset(metric.length / 2);
// //       if (t != null) return t.position;
// //     }
// //     return null;
// //   }

// //   Offset? _firstVerticalMidpoint(Path path) {
// //     final samples = _samplePath(path);
// //     if (samples.length < 2) return null;

// //     for (int i = 1; i < samples.length; i++) {
// //       final a = samples[i - 1];
// //       final b = samples[i];
// //       final isVertical = (a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() > 0.5;
// //       if (!isVertical) continue;

// //       int endIdx = i;
// //       while (endIdx < samples.length - 1) {
// //         final p = samples[endIdx];
// //         final q = samples[endIdx + 1];
// //         final stillVertical =
// //             (p.dx - q.dx).abs() < 0.5 && (p.dy - q.dy).abs() > 0.5;
// //         if (!stillVertical) break;
// //         endIdx++;
// //       }
// //       final top = samples[i - 1];
// //       final bottom = samples[endIdx];
// //       return Offset(top.dx, (top.dy + bottom.dy) / 2);
// //     }
// //     return null;
// //   }

// //   Offset? _endOfHorizontalSegment(Path path) {
// //     Offset? lastCorner;
// //     for (final metric in path.computeMetrics()) {
// //       bool wasHorizontal = false;
// //       for (double d = 0; d <= metric.length; d += 1) {
// //         final t = metric.getTangentForOffset(d);
// //         if (t == null) continue;
// //         final v = t.vector;
// //         final isVert = v.dx.abs() < 0.5 && v.dy.abs() > 0.5;
// //         final isHorz = v.dx.abs() > 0.5 && v.dy.abs() < 0.5;
// //         if (isHorz) {
// //           wasHorizontal = true;
// //         } else if (isVert && wasHorizontal) {
// //           lastCorner = t.position;
// //           wasHorizontal = false;
// //         }
// //       }
// //     }
// //     return lastCorner;
// //   }

// //   // Возвращает точку на последнем горизонтальном сегменте пути с заданной x-координатой
// //   Offset? _exitPlusPositionAtX(Path path, double? targetX) {
// //     if (targetX == null) return null;
// //     final segs = _extractSegments(path);
// //     if (segs.isEmpty) return null;

// //     _Seg? lastHorz;
// //     for (final s in segs) {
// //       final isHorz =
// //           (s.start.dy - s.end.dy).abs() < 0.5 &&
// //           (s.start.dx - s.end.dx).abs() > 0.5;
// //       if (isHorz) lastHorz = s;
// //     }
// //     if (lastHorz == null) return null;

// //     final xLeft = math.min(lastHorz.start.dx, lastHorz.end.dx);
// //     final xRight = math.max(lastHorz.start.dx, lastHorz.end.dx);
// //     if (targetX < xLeft - 0.5 || targetX > xRight + 0.5) return null;

// //     return Offset(targetX, lastHorz.start.dy);
// //   }
// // }

// // class _MergePoint {
// //   final double y;
// //   final String connId;
// //   const _MergePoint({required this.y, required this.connId});
// // }

// // class _Seg {
// //   final Offset start;
// //   final Offset end;
// //   const _Seg(this.start, this.end);
// // }
