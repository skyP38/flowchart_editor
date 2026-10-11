import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';
import 'graph_utils.dart';

/// Короткое описание пути: старт + последовательность точек
String _describePath(Path path) {
  final points = <Offset>[];
  for (final metric in path.computeMetrics()) {
    for (double d = 0; d <= metric.length; d += 5) {
      final t = metric.getTangentForOffset(d);
      if (t != null) points.add(t.position);
    }
    final endT = metric.getTangentForOffset(metric.length);
    if (endT != null) points.add(endT.position);
  }
  if (points.isEmpty) return '<пусто>';
  final head = points
      .take(6)
      .map((p) => '(${p.dx.toStringAsFixed(0)},${p.dy.toStringAsFixed(0)})');
  final tail = points.length > 6
      ? '… → (${points.last.dx.toStringAsFixed(0)},'
            '${points.last.dy.toStringAsFixed(0)})'
      : '';
  return '${head.join(' → ')} $tail';
}

void _log(String tag, String msg) {
  debugPrint('[conn][$tag] $msg');
}

// Вычисляет путь для связи в зависимости от портов источника и цели, а также от типа целевого блока
//
// Основные случаи:
//  - 'no' - обход блоков справа, вывод к цели;
//  - 'yes' - вертикальный спуск вниз;
//  - 'body'/'exit' - специальные порты блока For;
//  - 'loopback' - обратная связь от тела цикла к блоку For;
//  - обычная связь - прямая или с обходом, если цель = End.
Path buildConnectionPath({
  required ConnectionData conn,
  required Map<String, NodeWidgetData> nodes,
  required List<ConnectionData> connections,
  required Size nodeSize,
}) {
  final source = nodes[conn.sourceNodeName];
  final target = nodes[conn.targetNodeName];
  if (source == null || target == null) return Path();

  final path = Path();

  final srcPos = source.position;
  final tgtPos = target.position;
  final isEnd =
      target.node.data is TerminalBlock && target.node.data.text == 'End';

  _log(
    'begin',
    'conn ${conn.sourceNodeName}.${conn.sourcePort} → '
        '${conn.targetNodeName}.${conn.targetPort} '
        '(isEnd=$isEnd, '
        'src=(${srcPos.dx.toStringAsFixed(0)},${srcPos.dy.toStringAsFixed(0)}), '
        'tgt=(${tgtPos.dx.toStringAsFixed(0)},${tgtPos.dy.toStringAsFixed(0)}))',
  );

  if (conn.targetPort == 'loopback') {
    final start =
        source.position +
        Offset(nodeSize.width / 2, nodeSize.height); // из нижней грани заглушки
    final end =
        target.position + Offset(0, nodeSize.height / 2); // в левую грань For

    final bounds = GraphUtils.subtreeBounds(
      target.node.name,
      nodes,
      connections,
      nodeSize,
    );

    final double leftX = (bounds != null && bounds.left < end.dx)
        ? bounds.left - 20.0
        : end.dx - 20.0;

    final double bottomY = (bounds != null && bounds.bottom + 20 > start.dy)
        ? bounds.bottom + 20.0
        : start.dy + 20.0;

    path.moveTo(start.dx, start.dy);
    path.lineTo(start.dx, bottomY); // вниз — за нижнюю границу поддерева
    path.lineTo(leftX, bottomY); // влево — за левую границу поддерева
    path.lineTo(leftX, end.dy); // вверх — до центра For
    path.lineTo(end.dx, end.dy); // вправо — в левую грань For

    // const double gap = 20.0;
    // final mid1 = Offset(start.dx, start.dy + gap);
    // final mid2 = Offset(end.dx - gap, mid1.dy);
    // final mid3 = Offset(end.dx - gap, end.dy);
    // path.moveTo(start.dx, start.dy);
    // path.lineTo(mid1.dx, mid1.dy);
    // path.lineTo(mid2.dx, mid2.dy);
    // path.lineTo(mid3.dx, mid3.dy);
    // path.lineTo(end.dx, end.dy);
    _log('loopback', 'путь: ${_describePath(path)}');
    return path;
  }

  // Вычисление нижней границы
  double maxBottomY = 0;
  for (final entry in nodes.entries) {
    final bottom = entry.value.position.dy + nodeSize.height;
    if (bottom > maxBottomY) maxBottomY = bottom;
  }
  maxBottomY = maxBottomY - nodeSize.height - 10;
  const double endOffset = 0.0;
  final double endLineY = maxBottomY + endOffset;

  final sourcePos = source.position;
  final targetPos = target.position;
  // final isEnd =
  // target.node.data is TerminalBlock && target.node.data.text == 'End';

  if (conn.sourcePort == 'no') {
    final start = sourcePos + Offset(nodeSize.width, nodeSize.height / 2);
    final end = targetPos + Offset(nodeSize.width / 2, 0);
    if (isEnd) {
      final mid1 = Offset(start.dx + 30, start.dy);
      final mid2 = Offset(mid1.dx, endLineY);
      final mid3 = Offset(end.dx, mid2.dy);
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid1.dx, mid1.dy);
      path.lineTo(mid2.dx, mid2.dy);
      path.lineTo(mid3.dx, mid3.dy);
      path.lineTo(end.dx, end.dy);
      _log(
        'no→End',
        'endLineY=${endLineY.toStringAsFixed(0)}; '
            'путь: ${_describePath(path)}',
      );
    } else {
      final double safeX = end.dx > start.dx + 20 ? end.dx : start.dx + 20;
      final mid1 = Offset(safeX, start.dy);
      final mid2 = Offset(safeX, end.dy);
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid1.dx, mid1.dy);
      path.lineTo(mid2.dx, mid2.dy);
      path.lineTo(end.dx, end.dy);
      _log(
        'no',
        'safeX=${safeX.toStringAsFixed(0)}; '
            'путь: ${_describePath(path)}',
      );
    }
  } else if (conn.sourcePort == 'yes') {
    final start = sourcePos + Offset(nodeSize.width / 2, nodeSize.height);
    final end = targetPos + Offset(nodeSize.width / 2, 0);
    if (isEnd) {
      final mid1 = Offset(start.dx, endLineY);
      final mid2 = Offset(end.dx, endLineY);
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid1.dx, mid1.dy);
      path.lineTo(mid2.dx, mid2.dy);
      path.lineTo(end.dx, end.dy);
      _log(
        'yes→End',
        'endLineY=${endLineY.toStringAsFixed(0)}; '
            'путь: ${_describePath(path)}',
      );
    } else {
      path.moveTo(start.dx, start.dy); // ?
      path.lineTo(end.dx, end.dy); // ?
      _log('yes', 'прямая; путь: ${_describePath(path)}');
    }
  } else if (conn.sourcePort == 'body') {
    final start = sourcePos + Offset(nodeSize.width / 2, nodeSize.height);
    final end = targetPos + Offset(nodeSize.width / 2, 0);
    path.moveTo(start.dx, start.dy);
    path.lineTo(end.dx, end.dy);
    _log('body', 'прямая; путь: ${_describePath(path)}');
  } else if (conn.sourcePort == 'exit') {
    final start = sourcePos + Offset(nodeSize.width, nodeSize.height / 2);
    final end = targetPos + Offset(nodeSize.width / 2, 0);

    final bounds = GraphUtils.subtreeBounds(
      conn.sourceNodeName,
      nodes,
      connections,
      nodeSize,
    );

    final double rightX = (bounds != null && bounds.right + 30 > start.dx)
        ? bounds.right + 30.0
        : start.dx + 30.0;

    final double turnY =
        (bounds != null && bounds.bottom + 30 > start.dy + nodeSize.height)
        ? bounds.bottom + 30.0
        : start.dy + 30.0;

    // final maxBodyBottom = GraphUtils.maxBottomOfBodySubtree(
    //   conn.sourceNodeName,
    //   nodes,
    //   connections,
    //   nodeSize,
    // );
    // final maxBodyRight = GraphUtils.maxRightOfSubtree(
    //   conn.sourceNodeName,
    //   nodes,
    //   connections,
    //   nodeSize,
    // );

    // final double rightX;
    // if (maxBodyRight.isFinite && maxBodyRight > start.dx) {
    //   rightX = maxBodyRight + 30.0;
    // } else {
    //   rightX = start.dx + 30.0;
    // }

    // final double turnY;
    // if (maxBodyBottom > start.dy + nodeSize.height) {
    //   turnY = maxBodyBottom + 30.0;
    // } else {
    //   turnY = start.dy + 30.0;
    // }

    if (isEnd) {
      path.moveTo(start.dx, start.dy);
      path.lineTo(rightX, start.dy);
      path.lineTo(rightX, turnY);
      path.lineTo(end.dx, turnY);
      path.lineTo(end.dx, end.dy);
      _log(
        'exit→End',
        // 'maxBodyBottom=${maxBodyBottom.toStringAsFixed(0)}, '
        //     'maxBodyRight=${maxBodyRight.toStringAsFixed(0)}, '
        'rightX=${rightX.toStringAsFixed(0)}, '
            'turnY=${turnY.toStringAsFixed(0)}',
      );
      // final mid1 = Offset(start.dx + 30.0, turnY);
      // final mid2 = Offset(rightX, start.dy);
      // turnY);
      // final mid3 = Offset(end.dx, end.dy);
      // path.moveTo(start.dx, start.dy);
      // path.lineTo(mid1.dx, start.dy);
      // path.lineTo(mid1.dx, mid1.dy);
      // path.lineTo(mid2.dx, mid2.dy);
      // path.lineTo(mid3.dx, mid3.dy);
      // path.lineTo(end.dx, end.dy);
      // _log(
      //   'exit→End',
      //   'maxBodyBottom=${maxBodyBottom.toStringAsFixed(0)}, '
      //       'turnY=${turnY.toStringAsFixed(0)}; '
      //       'путь: ${_describePath(path)}',
      // );
    } else {
      final safeX = end.dx > rightX ? end.dx : rightX;
      // final double safeX = end.dx > start.dx + 20 ? end.dx : start.dx + 20;
      final mid1 = Offset(safeX, start.dy);
      final mid2 = Offset(safeX, end.dy);
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid1.dx, mid1.dy);
      path.lineTo(mid2.dx, mid2.dy);
      path.lineTo(end.dx, end.dy);
      _log(
        'exit',
        // 'maxBodyBottom=${maxBodyBottom.toStringAsFixed(0)}, '
        'safeX=${safeX.toStringAsFixed(0)}; '
            'путь: ${_describePath(path)}',
      );
    }
  } else {
    final start = sourcePos + Offset(nodeSize.width / 2, nodeSize.height);
    final end = targetPos + Offset(nodeSize.width / 2, 0);
    if (isEnd && end.dx != start.dx) {
      final mid1 = Offset(start.dx, start.dy + 20);
      final mid2 = Offset(mid1.dx, endLineY);
      final mid3 = Offset(end.dx, mid2.dy);
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid1.dx, mid1.dy);
      path.lineTo(mid2.dx, mid2.dy);
      path.lineTo(mid3.dx, mid3.dy);
      path.lineTo(end.dx, end.dy);
      _log(
        'out→End',
        'endLineY=${endLineY.toStringAsFixed(0)}; '
            'путь: ${_describePath(path)}',
      );
    } else {
      path.moveTo(start.dx, start.dy);
      path.lineTo(end.dx, end.dy);
      _log('out', 'прямая; путь: ${_describePath(path)}');
    }
  }
  return path;
}
