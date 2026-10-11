import 'package:flutter/material.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';

/// Утилиты обхода графа блок-схемы
class GraphUtils {
  // Рекурсивно собирает имена узлов, достижимых из start,
  // но не включает блок End
  static void collectSubtreeExcludingEnd(
    String start,
    Set<String> collected,
    Map<String, NodeWidgetData> nodes,
    List<ConnectionData> connections,
  ) {
    if (collected.contains(start)) return;
    final node = nodes[start]?.node;
    if (node != null && node.data is TerminalBlock && node.data.text == 'End') {
      return;
    }
    collected.add(start);
    final children = connections
        .where((c) => c.sourceNodeName == start)
        .toList();
    for (final child in children) {
      collectSubtreeExcludingEnd(
        child.targetNodeName,
        collected,
        nodes,
        connections,
      );
    }
  }

  // Максимальная нижняя граница среди всех блоков поддерева тела цикла
  // для указанного блока For
  // Если тела нет - возвращает double.negativeInfinity
  static double maxBottomOfBodySubtree(
    String forNodeName,
    Map<String, NodeWidgetData> nodes,
    List<ConnectionData> connections,
    Size nodeSize,
  ) {
    String? bodyRoot;
    for (final conn in connections) {
      if (conn.sourceNodeName == forNodeName && conn.sourcePort == 'body') {
        bodyRoot = conn.targetNodeName;
        break;
      }
    }
    if (bodyRoot == null) return double.negativeInfinity;

    final Set<String> subtree = {};
    collectSubtreeExcludingEnd(bodyRoot, subtree, nodes, connections);

    double maxBottom = 0;
    for (final name in subtree) {
      final data = nodes[name];
      if (data != null) {
        final bottom = data.position.dy + nodeSize.height;
        if (bottom > maxBottom) maxBottom = bottom;
      }
    }
    return maxBottom;
  }

  /// Максимальная правая граница поддерева тела цикла для указанного блока For
  static double maxRightOfSubtree(
    String forNodeName,
    Map<String, NodeWidgetData> nodes,
    List<ConnectionData> connections,
    Size nodeSize,
  ) {
    String? bodyRoot;
    for (final conn in connections) {
      if (conn.sourceNodeName == forNodeName && conn.sourcePort == 'body') {
        bodyRoot = conn.targetNodeName;
        break;
      }
    }
    if (bodyRoot == null) return double.negativeInfinity;

    final Set<String> visited = {forNodeName}; // не возвращаемся в сам For
    final queue = <String>[bodyRoot];
    double maxRight = 0;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      final n = nodes[current]?.node;
      if (n != null && n.data is TerminalBlock && n.data.text == 'End') {
        continue;
      }

      final pos = nodes[current]!.position;
      final right = pos.dx + nodeSize.width;
      if (right > maxRight) maxRight = right;

      for (final conn in connections) {
        if (conn.sourceNodeName == current && conn.targetPort != 'loopback') {
          queue.add(conn.targetNodeName);
        }
      }
    }
    return maxRight;
  }

  // Прямоугольник-обертка вокруг всего поддерева узла rootName:
  // BFS по всем исходящим связям (кроме loopback), с остановкой на End
  static Rect? subtreeBounds(
    String rootName,
    Map<String, NodeWidgetData> nodes,
    List<ConnectionData> connections,
    Size nodeSize,
  ) {
    final visited = <String>{};
    final queue = <String>[rootName];
    Rect? bounds;

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      final node = nodes[current]?.node;
      if (node != null &&
          node.data is TerminalBlock &&
          node.data.text == 'End') {
        continue;
      }

      final data = nodes[current];
      if (data == null) continue;

      final r = Rect.fromLTWH(
        data.position.dx,
        data.position.dy,
        nodeSize.width,
        nodeSize.height,
      );
      bounds = bounds == null ? r : bounds.expandToInclude(r);

      for (final conn in connections) {
        if (conn.sourceNodeName == current && conn.targetPort != 'loopback') {
          queue.add(conn.targetNodeName);
        }
      }
    }

    return bounds;
  }
}
