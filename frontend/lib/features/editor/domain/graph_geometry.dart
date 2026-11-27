import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/editor_models.dart';
import '../models/flow_models.dart';
import 'flowchart_graph.dart';

/// Чистые геометрические запросы к графу, не зависящие от [LayoutSpacing].
///
/// Сюда вынесены обходы графа, которые до этого существовали в трёх-четырёх
/// копиях (`LayoutEngine`, `ConnectionRouter`, `InsertionPointsService`) и
/// могли разойтись по семантике. Все методы — статические, детерминированные,
/// без побочных эффектов. Где нужен размер ноды — принимают [nodeSize] явно;
/// [spacing] сюда не проникает, чтобы файл тестировался без [LayoutEngine].
class GraphGeometry {
  const GraphGeometry._();

  // ─────────────────────────────── обходы ───────────────────────────────

  /// Все узлы, достижимые из [root] по обычным (не loopback) рёбрам.
  static Set<String> subtreeNodes(FlowchartGraph g, String root) {
    final result = <String>{};
    void dfs(String n) {
      if (result.contains(n)) return;
      result.add(n);
      if (g.isEnd(n)) return;
      for (final c in g.outgoing[n] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        dfs(c.targetNodeName);
      }
    }

    dfs(root);
    return result;
  }

  /// Все узлы body-поддерева [root], не выходящего за exit-рёбра [stopExitOf].
  ///
  /// Отличается от [subtreeNodes] тем, что останавливается не на узле-цели,
  /// а на **рёбрах**, у которых `sourceNodeName == stopExitOf && sourcePort == 'exit'`.
  /// Нужно для `LayoutEngine._adjustForExitRanks`, чтобы не выскочить
  /// из тела текущего For.
  static Set<String> bodySubtreeNodes(
    FlowchartGraph g,
    String root, {
    required String stopExitOf,
  }) {
    final result = <String>{};
    void dfs(String n) {
      if (result.contains(n)) return;
      result.add(n);
      if (g.isEnd(n)) return;
      for (final c in g.outgoing[n] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit' && c.sourceNodeName == stopExitOf) continue;
        dfs(c.targetNodeName);
      }
    }

    dfs(root);
    return result;
  }

  /// Количество For-блоков, вложенных в тело [forName] на любой глубине.
  ///
  /// BFS только по body-ветке; не выходит через `exit forName` и через
  /// loopback-рёбра. Сам [forName] не считается — даже если внутри тела
  /// лежит For с тем же именем (self-loop).
  static int innerForCount(FlowchartGraph g, String forName) {
    final bodyConn = (g.outgoing[forName] ?? const <ConnectionData>[])
        .firstWhereOrNull((c) => c.sourcePort == 'body');
    if (bodyConn == null) return 0;
    if (bodyConn.targetNodeName == forName) return 0;

    final visited = <String>{};
    final queue = <String>[bodyConn.targetNodeName];
    int count = 0;
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      final n = g.nodes[cur];
      if (n == null) continue;
      if (n.data is ForBlock) count++;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit' && c.sourceNodeName == forName) continue;
        queue.add(c.targetNodeName);
      }
    }
    return count;
  }

  /// Количество For-предков у [forName] (0 — внешний цикл).
  ///
  /// Ищет ближайшего предка по body-ребру: если `body`-ребро ведёт прямо в
  /// [forName] — родитель найден; иначе — тот For, чьё `body`-поддерево
  /// содержит [forName] и является минимальным по размеру.
  static int forAncestorCount(FlowchartGraph g, String forName) {
    int count = 0;
    String cur = forName;
    final visited = <String>{forName};

    while (true) {
      String? bestParent;
      int bestSize = 1 << 30;

      for (final c in g.connections) {
        if (c.sourcePort != 'body') continue;
        if (visited.contains(c.sourceNodeName)) continue;

        if (c.targetNodeName == cur) {
          bestParent = c.sourceNodeName;
          bestSize = 0;
          break;
        }

        final sub = subtreeNodes(g, c.targetNodeName);
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

  /// Максимальная глубина вложенности For-ов в графе.
  static int maxForDepth(FlowchartGraph g) {
    int maxDepth = 0;
    for (final e in g.nodes.entries) {
      if (e.value.data is! ForBlock) continue;
      final a = forAncestorCount(g, e.key);
      if (a > maxDepth) maxDepth = a;
    }
    return maxDepth;
  }

  /// Достижим ли [to] из [from] по цепочке `yes`/`out`-рёбер.
  ///
  /// Используется в `LayoutEngine`, чтобы отличить «no-ветвь, которая на
  /// самом деле rejoin через yes» от настоящей отдельной ветви. Семантика
  /// ровно как у прежнего `ConnectionRouter._reachableViaYesOut`.
  static bool reachableViaYesOut(FlowchartGraph g, String from, String to) {
    if (from == to) return true;
    final visited = <String>{from};
    final queue = <String>[from];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.sourcePort != 'yes' && c.sourcePort != 'out') continue;
        if (c.targetNodeName == to) return true;
        if (visited.add(c.targetNodeName)) queue.add(c.targetNodeName);
      }
    }
    return false;
  }

  // ──────────────────────────── нижние границы ────────────────────────────

  /// Нижняя граница тела цикла [forName] (max `node.y + h` по body-ветке).
  ///
  /// Не выходит за `exit forName` и за loopback-рёбра. Для self-loop
  /// (`body → forName`) возвращает низ самого [forName].
  static double bodySubtreeBottom(
    FlowchartGraph g,
    String forName,
    Size nodeSize,
  ) {
    final bodyConn = (g.outgoing[forName] ?? const <ConnectionData>[])
        .firstWhereOrNull((c) => c.sourcePort == 'body');
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
      final b = n.position.dy + nodeSize.height;
      if (b > maxBottom) maxBottom = b;
      if (g.isEnd(cur)) continue;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit' && c.sourceNodeName == forName) continue;
        queue.add(c.targetNodeName);
      }
    }
    return maxBottom;
  }

  /// Нижняя граница **обеих** веток LogicBlock [logicName] (yes + no).
  ///
  /// Нужна для огибания: внешняя ветвь должна пройти ниже любых блоков,
  /// добавленных в yes- или no-ветку этого логического блока.
  static double logicBranchBottom(
    FlowchartGraph g,
    String logicName,
    Size nodeSize,
  ) {
    final node = g.nodes[logicName];
    if (node == null) return 0;

    double maxBottom = node.position.dy + nodeSize.height;
    final visited = <String>{logicName};
    final queue = <String>[];
    for (final c in g.outgoing[logicName] ?? const <ConnectionData>[]) {
      if (c.targetPort == 'loopback') continue;
      queue.add(c.targetNodeName);
    }
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (g.isEnd(cur)) continue;
      final n = g.nodes[cur];
      if (n == null) continue;
      final b = n.position.dy + nodeSize.height;
      if (b > maxBottom) maxBottom = b;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return maxBottom;
  }

  /// Нижняя граница **только yes-ветви** LogicBlock [logicName].
  ///
  /// Нужна `no`-коридору: он должен огибать yes-поддерево снизу, но не
  /// обязан спускаться ниже no-ветви (её он огибает сбоку).
  static double logicYesSubtreeBottom(
    FlowchartGraph g,
    String logicName,
    Size nodeSize,
  ) {
    final yesConn = (g.outgoing[logicName] ?? const <ConnectionData>[])
        .firstWhereOrNull((c) => c.sourcePort == 'yes');
    if (yesConn == null) return 0;

    final visited = <String>{};
    final queue = <String>[yesConn.targetNodeName];
    double maxBottom = 0;

    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (g.isEnd(cur)) continue;

      final n = g.nodes[cur];
      if (n == null) continue;
      final b = n.position.dy + nodeSize.height;
      if (b > maxBottom) maxBottom = b;

      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return maxBottom;
  }
}
