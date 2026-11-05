import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../factories/node_factory.dart';
import '../models/editor_models.dart';

class DiagramScene {
  final Size canvasSize;
  final Offset? startPosition;
  final List<ConnectionItem> connections;
  final List<NodeItem> nodes;
  final GridScene grid;

  const DiagramScene({
    required this.canvasSize,
    required this.startPosition,
    required this.connections,
    required this.nodes,
    required this.grid,
  });
}

class ArrowItem {
  final Offset tip;
  final double angle; // радианы
  const ArrowItem(this.tip, this.angle);

  Offset get direction => Offset(math.cos(angle), math.sin(angle));
}

class ConnectionItem {
  final ConnectionData connection;
  final Path path;
  final List<ArrowItem> arrows;
  const ConnectionItem(this.connection, this.path, this.arrows);
}

class NodeItem {
  final NodeModel node;
  final Path outline;
  final List<Path> extras;
  final Offset textCenter;
  const NodeItem({
    required this.node,
    required this.outline,
    required this.extras,
    required this.textCenter,
  });
}

class GridScene {
  final List<GridLineItem> lines;
  final List<GridLabelItem> labels;
  const GridScene({required this.lines, required this.labels});

  static const empty = GridScene(lines: [], labels: []);
}

class GridLineItem {
  final Offset from;
  final Offset to;
  const GridLineItem(this.from, this.to);
}

class GridLabelItem {
  final Offset position; // позиция верхнего левого угла текста
  final String text;
  final bool isColumn; // true - цифра (сверху), false - буква (слева)
  const GridLabelItem(this.position, this.text, {required this.isColumn});
}
