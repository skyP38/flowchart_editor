import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';

// Рисует все соединения между блоками и "+" на связи при добавлении элемента
class ConnectionPainter extends CustomPainter {
  final List<ConnectionData> connections;
  final Map<String, NodeWidgetData> nodes;
  final Size nodeSize;
  final String? selectedConnectionId;
  final List<InsertionPoint> insertionPoints;

  ConnectionPainter({
    required this.connections,
    required this.nodes,
    required this.nodeSize,
    this.selectedConnectionId,
    required this.insertionPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Поиск нижней границы всех блоков
    double maxBottomY = 0;
    for (final entry in nodes.entries) {
      final bottom = entry.value.position.dy + nodeSize.height;
      if (bottom > maxBottomY) maxBottomY = bottom;
    }
    maxBottomY = maxBottomY - nodeSize.height - 10;
    const double endOffset = 0.0;
    final double endLineY = maxBottomY + endOffset;

    for (final conn in connections) {
      final source = nodes[conn.sourceNodeName];
      final target = nodes[conn.targetNodeName];
      if (source == null || target == null) continue;

      final isSelected = conn.id != null && conn.id == selectedConnectionId;
      final paint = Paint()
        ..color = isSelected ? Colors.blue : Colors.black
        ..strokeWidth = isSelected ? 4 : 2
        ..style = PaintingStyle.stroke;

      if (conn.targetPort == 'loopback') {
        final start =
            source.position + Offset(nodeSize.width / 2, nodeSize.height);
        final end = target.position + Offset(0, nodeSize.height / 2);
        const double up = 20.0;
        final mid1 = Offset(start.dx, start.dy + up);
        final mid2 = Offset(end.dx - 20, mid1.dy);
        final mid3 = Offset(end.dx - 20, end.dy);
        final mid4 = Offset(end.dx, end.dy);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(mid1.dx, mid1.dy)
          ..lineTo(mid2.dx, mid2.dy)
          ..lineTo(mid3.dx, mid3.dy)
          ..lineTo(mid4.dx, mid4.dy)
          ..lineTo(end.dx, end.dy);
        canvas.drawPath(path, paint);
        continue;
      }

      if (conn.sourcePort == 'no') {
        final start =
            source.position + Offset(nodeSize.width, nodeSize.height / 2);
        final end = target.position + Offset(nodeSize.width / 2, 0);
        final targetNode = nodes[conn.targetNodeName]?.node;
        final isEnd =
            targetNode != null &&
            targetNode.data is TerminalBlock &&
            targetNode.data.text == 'End';

        if (isEnd) {
          final mid1 = Offset(start.dx + 30, start.dy);
          final mid2 = Offset(mid1.dx, endLineY);
          final mid3 = Offset(end.dx, mid2.dy);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(mid3.dx, mid3.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
        } else {
          // вправо -> вниз -> влево
          final mid1 = Offset(end.dx, start.dy);
          final mid2 = Offset(mid1.dx, end.dy);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
          print("no noend");
        }
      } else if (conn.sourcePort == 'yes') {
        final start =
            source.position + Offset(nodeSize.width / 2, nodeSize.height);
        final end = target.position + Offset(nodeSize.width / 2, 0);
        final targetNode = nodes[conn.targetNodeName]?.node;
        final isEnd =
            targetNode != null &&
            targetNode.data is TerminalBlock &&
            targetNode.data.text == 'End';
        print(end.dx);
        print(start.dx);
        if (isEnd && end.dx != start.dx) {
          const double verticalStep = 20.0;
          // final mid1 = Offset(start.dx, start.dy + verticalStep);
          final mid1 = Offset(start.dx, endLineY);
          // final mid2 = Offset(end.dx, endLineY);
          final mid2 = Offset(end.dx, endLineY);
          // final mid2 = Offset(end.dx, mid1.dy);

          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
          print("yes");
        } else if (isEnd) {
          canvas.drawLine(start, end, paint);
        } else {
          // вправо -> вниз -> влево
          final sourcePos =
              source.position + Offset(nodeSize.width / 2, nodeSize.height);
          final targetPos = target.position + Offset(nodeSize.width / 2, 0);
          canvas.drawLine(sourcePos, targetPos, paint);
        }
      } else if (conn.sourcePort == 'body') {
        final start =
            source.position + Offset(nodeSize.width / 2, nodeSize.height);
        final end = target.position + Offset(nodeSize.width / 2, 0);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
        canvas.drawPath(path, paint);
      } else if (conn.sourcePort == 'exit') {
        final start =
            source.position + Offset(nodeSize.width, nodeSize.height / 2);
        final end = target.position + Offset(nodeSize.width / 2, 0);
        final targetNode = nodes[conn.targetNodeName]?.node;
        final isEnd =
            targetNode != null &&
            targetNode.data is TerminalBlock &&
            targetNode.data.text == 'End';

        final double maxBodyBottom = _getMaxBottomOfBodySubtree(
          conn.sourceNodeName,
        );
        double down = 30.0;
        double turnY = start.dy;
        if (maxBodyBottom > start.dy + nodeSize.height) {
          down = (maxBodyBottom - start.dy - nodeSize.height) + 30.0;
          turnY = start.dy + nodeSize.height + down;
        } else {
          turnY = start.dy + 30.0;
        }

        if (isEnd) {
          final mid1 = Offset(start.dx + 20, start.dy);
          final mid2 = Offset(start.dx + 20, turnY);
          final mid3 = Offset(end.dx, turnY);
          final mid4 = Offset(end.dx, mid2.dy);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(mid3.dx, mid3.dy)
            ..lineTo(mid4.dx, mid4.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
        } else {
          final mid1 = Offset(end.dx, start.dy);
          // final mid2 = Offset(end.dx, mid1.dy);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            // ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
        }
      } else {
        final start =
            source.position + Offset(nodeSize.width / 2, nodeSize.height);
        final end = target.position + Offset(nodeSize.width / 2, 0);
        final targetNode = nodes[conn.targetNodeName]?.node;
        final isEnd =
            targetNode != null &&
            targetNode.data is TerminalBlock &&
            targetNode.data.text == 'End';

        if (isEnd && end.dx != start.dx) {
          // Путь для End: вниз -> влево -> вниз
          final mid1 = Offset(start.dx, start.dy + 20);
          final mid2 = Offset(mid1.dx, endLineY);
          final mid3 = Offset(end.dx, mid2.dy);
          // final mid2 = Offset(end.dx, mid1.dy);
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid1.dx, mid1.dy)
            ..lineTo(mid2.dx, mid2.dy)
            ..lineTo(mid3.dx, mid3.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, paint);
        } else {
          final sourcePos =
              source.position + Offset(nodeSize.width / 2, nodeSize.height);
          final targetPos = target.position + Offset(nodeSize.width / 2, 0);
          canvas.drawLine(sourcePos, targetPos, paint);
        }
      }
    }

    // Кружки для вставки блоков
    for (final point in insertionPoints) {
      // Заливка кружка
      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point.position, 10, fillPaint);
      // Обводка
      final strokePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(point.position, 10, strokePaint);
      // Плюс
      final plusPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        point.position + const Offset(-4, 0),
        point.position + const Offset(4, 0),
        plusPaint,
      );
      canvas.drawLine(
        point.position + const Offset(0, -4),
        point.position + const Offset(0, 4),
        plusPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.nodes != nodes ||
        oldDelegate.nodeSize != nodeSize ||
        oldDelegate.selectedConnectionId != selectedConnectionId;
  }

  // Возвращает максимальную нижнюю границу у поддерева
  // Нужно чтобы ребро exit обходило тело цикла снизу
  double _getMaxBottomOfBodySubtree(String forNodeName) {
    String? bodyRoot;
    for (final conn in connections) {
      if (conn.sourceNodeName == forNodeName && conn.sourcePort == 'body') {
        bodyRoot = conn.targetNodeName;
        break;
      }
    }
    if (bodyRoot == null) return double.negativeInfinity;
    final Set<String> subtree = {};
    _collectSubtreeExcludingEnd(bodyRoot, subtree, nodes, connections);
    double maxBottom = 0;
    for (final nodeName in subtree) {
      final nodeData = nodes[nodeName];
      if (nodeData != null) {
        final bottom = nodeData.position.dy + nodeSize.height;
        if (bottom > maxBottom) maxBottom = bottom;
      }
    }
    return maxBottom;
  }

  // Рекурсивный обход поддерева с остановкой на блоке End
  void _collectSubtreeExcludingEnd(
    String startNode,
    Set<String> collected,
    Map<String, NodeWidgetData> nodes,
    List<ConnectionData> connections,
  ) {
    if (collected.contains(startNode)) return;
    final node = nodes[startNode]?.node;
    if (node != null && node.data is TerminalBlock && node.data.text == 'End')
      return;
    collected.add(startNode);
    final children = connections
        .where((c) => c.sourceNodeName == startNode)
        .toList();
    for (final child in children) {
      _collectSubtreeExcludingEnd(
        child.targetNodeName,
        collected,
        nodes,
        connections,
      );
    }
  }
}
