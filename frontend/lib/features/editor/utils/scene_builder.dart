import 'package:flutter/material.dart';

import '../domain/connection_router.dart';
import '../domain/flowchart_graph.dart';
import '../domain/layout_engine.dart';
import '../factories/node_factory.dart';
import '../utils/node_shape_geometry.dart';
import 'diagram_scene.dart';

// Универсальный класс для рисования всего
class SceneBuilder {
  final ConnectionRouter router;
  final Size nodeSize;
  final LayoutSpacing spacing;

  SceneBuilder({
    required this.router,
    required this.nodeSize,
    required this.spacing,
  });

  DiagramScene build({
    required FlowchartGraph graph,
    required Size canvasSize,
    required bool showGrid,
    required bool showLabels,
  }) {
    final connections = <ConnectionItem>[];
    for (final c in graph.connections) {
      final routed = router.build(c, graph);
      final arrows = routed.arrows
          .map((a) => ArrowItem(a.position, a.angle))
          .toList();
      connections.add(ConnectionItem(c, routed.path, arrows));
    }

    final nodes = <NodeItem>[];
    for (final n in graph.nodes.values) {
      final outline = NodeShapeGeometry.outline(
        nodeSize,
        n.data,
      ).shift(n.position);
      final extras = NodeShapeGeometry.extras(
        nodeSize,
        n.data,
      ).map((p) => p.shift(n.position)).toList();
      nodes.add(
        NodeItem(
          node: n,
          outline: outline,
          extras: extras,
          textCenter:
              n.position + Offset(nodeSize.width / 2, nodeSize.height / 2),
        ),
      );
    }

    final start = graph.findStart();
    final grid = (start == null || (!showGrid && !showLabels))
        ? GridScene.empty
        : _buildGrid(
            start: start,
            canvasSize: canvasSize,
            showLines: showGrid,
            showLabels: showLabels,
          );

    return DiagramScene(
      canvasSize: canvasSize,
      startPosition: start?.position,
      connections: connections,
      nodes: nodes,
      grid: grid,
    );
  }

  GridScene _buildGrid({
    required NodeModel start,
    required Size canvasSize,
    required bool showLines,
    required bool showLabels,
  }) {
    final lines = <GridLineItem>[];
    final labels = <GridLabelItem>[];

    final shiftX = (spacing.stepX - nodeSize.width) / 2;
    final shiftY = (spacing.stepY - nodeSize.height) / 2;
    final startBoundaryX = start.position.dx - shiftX;
    final startBoundaryY = start.position.dy - shiftY;

    final firstCol = (-startBoundaryX / spacing.stepX).floor();
    final lastCol = ((canvasSize.width - startBoundaryX) / spacing.stepX)
        .ceil();
    for (int col = firstCol; col <= lastCol; col++) {
      final x = startBoundaryX + col * spacing.stepX;
      if (x < 0 || x > canvasSize.width) continue;
      if (showLines) {
        lines.add(GridLineItem(Offset(x, 0), Offset(x, canvasSize.height)));
      }
      if (showLabels) {
        final labelX = x + spacing.stepX / 2;
        if (labelX >= 0 && labelX <= canvasSize.width) {
          labels.add(
            GridLabelItem(Offset(labelX, 4), '${col + 1}', isColumn: true),
          );
        }
      }
    }

    final firstRow = (-startBoundaryY / spacing.stepY).floor();
    final lastRow = ((canvasSize.height - startBoundaryY) / spacing.stepY)
        .ceil();
    for (int row = firstRow; row <= lastRow; row++) {
      final y = startBoundaryY + row * spacing.stepY;
      if (y < 0 || y > canvasSize.height) continue;
      if (showLines) {
        lines.add(GridLineItem(Offset(0, y), Offset(canvasSize.width, y)));
      }
      if (showLabels) {
        final labelY = y + spacing.stepY / 2;
        if (labelY >= 0 && labelY <= canvasSize.height) {
          labels.add(
            GridLabelItem(
              Offset(4, labelY),
              _numberToLetter(row),
              isColumn: false,
            ),
          );
        }
      }
    }

    return GridScene(lines: lines, labels: labels);
  }

  static String _numberToLetter(int n) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String result = '';
    while (n >= 0) {
      result = alphabet[n % 26] + result;
      n = (n / 26).floor() - 1;
      if (n < 0) break;
    }
    return result;
  }
}
