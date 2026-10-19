import 'package:flowchart_editor_frontend/features/editor/domain/layout_engine.dart';
import 'package:flutter/material.dart';

import '../constants/diagram_constants.dart';
import '../factories/node_factory.dart';
import '../painters/grid_labels_painter.dart';
import '../domain/connection_router.dart';
import '../domain/flowchart_graph.dart';
import 'node_shape_geometry.dart';

class SvgExporter {
  SvgExporter._();

  static String export({
    required FlowchartGraph graph,
    required ConnectionRouter router,
    required Size nodeSize,
    required LayoutSpacing spacing,
    required Size canvasSize,
    required bool showGrid,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${canvasSize.width}" height="${canvasSize.height}">',
    );

    // Фон
    buffer.writeln('<rect width="100%" height="100%" fill="white"/>');

    // Сетка
    if (showGrid) {
      final start = graph.findStart();

      if (start != null) {
        buffer.write(
          _buildGridSvg(
            canvasSize: canvasSize,
            startPosition: start.position,
            stepX: spacing.stepX - GridConstants.stepXExtra,
            stepY: spacing.stepY - GridConstants.stepYExtra,
            // stepX: nodeSize.width,
            // stepY: nodeSize.height,
          ),
        );
      }
    }

    // Связи
    for (final conn in graph.connections) {
      final path = router.build(conn, graph);
      final d = _pathToSvgPath(path);
      if (d.isNotEmpty) {
        buffer.writeln(
          '<path d="$d" stroke="black" stroke-width="2" fill="none" />',
        );
      }
    }

    // Узлы
    for (final entry in graph.nodes.entries) {
      buffer.writeln(
        _buildNodeSvg(
          node: entry.value,
          pos: entry.value.position,
          size: nodeSize,
        ),
      );
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  // Path в строку SVG
  static String _pathToSvgPath(Path path) {
    final List<String> parts = [];
    for (final metric in path.computeMetrics()) {
      for (double dist = 0; dist <= metric.length; dist += 1) {
        final tangent = metric.getTangentForOffset(dist);
        if (tangent != null) {
          final p = tangent.position;
          parts.add(dist == 0 ? 'M ${p.dx} ${p.dy}' : 'L ${p.dx} ${p.dy}');
        }
      }
    }
    return parts.join(' ');
  }

  // Генерирует SVG для одного блока: фигура + текст
  static String _buildNodeSvg({
    required NodeModel node,
    required Offset pos,
    required Size size,
  }) {
    // контур и доп. линии из единого источника геометрии
    final outline = NodeShapeGeometry.outline(
      size,
      node.data,
    ).shift(pos); // сдвиг из локальных (0,0) в абсолютные координаты
    final extras = NodeShapeGeometry.extras(
      size,
      node.data,
    ).map((p) => p.shift(pos)).toList();

    final sb = StringBuffer();

    // Основной контур: SVG-path, белая заливка
    sb.writeln(
      '<path d="${_pathToSvgPath(outline)}" '
      'stroke="black" stroke-width="2" fill="white"/>',
    );

    // Дополнительные линии (сейчас только у подпрограммы)
    for (final e in extras) {
      sb.writeln(
        '<path d="${_pathToSvgPath(e)}" '
        'stroke="black" stroke-width="2" fill="none"/>',
      );
    }

    // Текст по центру блока
    final cx = pos.dx + size.width / 2;
    final cy = pos.dy + size.height / 2;
    sb.writeln(
      '<text x="$cx" y="$cy" text-anchor="middle" '
      'dominant-baseline="middle" font-family="Arial" '
      'font-size="14" fill="black">${_escapeXml(node.data.text)}</text>',
    );

    return sb.toString();
  }

  // Генерирует SVG-разметку сетки с подписями столбцов (цифры)
  // и строк (буквы), отсчитываемыми от позиции блока Start
  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _buildGridSvg({
    required Size canvasSize,
    required Offset startPosition,
    required double stepX,
    required double stepY,
  }) {
    final buffer = StringBuffer();
    const textStyle = 'font-family="Arial" font-size="18" fill="#666666"';

    // Подписи столбцов (цифры) сверху
    int firstCol = ((startPosition.dx) / stepX).floor();
    int lastCol = ((canvasSize.width - startPosition.dx) / stepX).ceil();
    for (int col = firstCol; col <= lastCol; col++) {
      final stepXgrid = stepX + GridConstants.stepXExtra;
      final startCenterX = startPosition.dx + stepX / 2;
      double x = startCenterX + col * stepXgrid;
      if (x < 0 || x > canvasSize.width) continue;
      final number = col + 1;
      buffer.writeln(
        '<text x="$x" y="20" text-anchor="middle" $textStyle>$number</text>',
      );
    }

    // Подписи строк (буквы) слева
    final stepYgrid = stepY + GridConstants.stepYExtra;
    final double startCenterY = startPosition.dy + stepY / 2;
    int firstRow = ((0 - startCenterY) / stepY).floor();
    int lastRow = ((canvasSize.height - startCenterY) / stepY).ceil();
    for (int row = firstRow; row <= lastRow; row++) {
      double y = startCenterY + row * stepYgrid;
      if (y < 0 || y > canvasSize.height) continue;
      String letter = numberToLetter(row);
      buffer.writeln(
        '<text x="20" y="$y" text-anchor="middle" dominant-baseline="middle" $textStyle>$letter</text>',
      );
    }

    return buffer.toString();
  }
}
