import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/flow_models.dart';
import 'flowchart_graph.dart';

class LayoutSpacing {
  final double stepX;
  final double stepY;
  const LayoutSpacing({required this.stepX, required this.stepY});
}

// rank - длина самого длинного пути от Start (loopback игнорируется)
// column - номер «ветки», out/yes/body - та же колонка;
// no/exit - новая колонка справа от всего, что занято main-поддеревом
class LayoutEngine {
  final Size nodeSize;
  final LayoutSpacing spacing;

  const LayoutEngine({required this.nodeSize, required this.spacing});

  Map<String, Offset> compute(FlowchartGraph g) {
    final start = g.findStart();
    if (start == null) return const {};

    // 1. Ранги (Y)
    final ranks = <String, int>{};
    _assignRanks(start.name, 0, g, ranks, {});

    // Выход каждого For должен лежать ниже всего его тела
    _adjustForExitRanks(g, ranks);

    // End - на самом низком ранге
    _pushEndToBottom(g, ranks);

    // 2. Колонки (X)
    final cols = <String, int>{};
    _assignColumns(start.name, 0, g, cols);

    // 3. Сборка
    final result = <String, Offset>{};
    for (final name in g.nodes.keys) {
      final r = ranks[name] ?? 0;
      final c = cols[name] ?? 0;
      result[name] = Offset(
        start.position.dx + c * spacing.stepX,
        start.position.dy + r * spacing.stepY,
      );
    }
    return result;
  }

  void _assignRanks(
    String node,
    int rank,
    FlowchartGraph g,
    Map<String, int> ranks,
    Set<String> inProgress,
  ) {
    if ((ranks[node] ?? -1) >= rank) return;
    if (!inProgress.add(node))
      return; // защита от циклов (loopback уже отфильтрован)
    ranks[node] = rank;
    for (final c in g.outgoing[node] ?? const []) {
      if (c.targetPort == 'loopback') continue;
      _assignRanks(c.targetNodeName, rank + 1, g, ranks, inProgress);
    }
    inProgress.remove(node);
  }

  // Для каждого For: exit-цель должна быть на ранг ниже, чем самый
  // глубокий узел тела
  void _adjustForExitRanks(FlowchartGraph g, Map<String, int> ranks) {
    final fors =
        g.nodes.entries
            .where((e) => e.value.data is ForBlock)
            .map((e) => e.key)
            .toList()
          ..sort((a, b) => (ranks[b] ?? 0).compareTo(ranks[a] ?? 0));

    for (final forName in fors) {
      final bodyConn = (g.outgoing[forName] ?? const []).firstWhereOrNull(
        (c) => c.sourcePort == 'body',
      );
      final exitConn = (g.outgoing[forName] ?? const []).firstWhereOrNull(
        (c) => c.sourcePort == 'exit',
      );
      if (bodyConn == null || exitConn == null) continue;

      final bodySubtree = _subtreeNodes(g, bodyConn.targetNodeName);
      int maxBodyRank = ranks[forName] ?? 0;
      for (final n in bodySubtree) {
        final r = ranks[n] ?? 0;
        if (r > maxBodyRank) maxBodyRank = r;
      }

      final desired = maxBodyRank + 1;
      final current = ranks[exitConn.targetNodeName] ?? 0;
      final delta = desired - current;
      if (delta <= 0) continue;

      final exitSubtree = _subtreeNodes(g, exitConn.targetNodeName);
      for (final n in exitSubtree) {
        if (g.isEnd(n)) continue; // End двигаем отдельно
        ranks[n] = (ranks[n] ?? 0) + delta;
      }
    }
  }

  void _pushEndToBottom(FlowchartGraph g, Map<String, int> ranks) {
    String? endName;
    for (final e in g.nodes.entries) {
      if (g.isEnd(e.key)) {
        endName = e.key;
        break;
      }
    }
    if (endName == null) return;

    int maxOther = 0;
    for (final e in ranks.entries) {
      if (e.key == endName) continue;
      if (e.value > maxOther) maxOther = e.value;
    }
    ranks[endName] = maxOther + 1;
  }

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

  // Возвращает максимальный номер колонки, занятый поддеревом node
  int _assignColumns(
    String node,
    int column,
    FlowchartGraph g,
    Map<String, int> cols,
  ) {
    if (cols.containsKey(node)) return cols[node]!;

    final isEnd = g.isEnd(node);
    cols[node] = isEnd ? 0 : column;
    if (isEnd) return 0;

    // cols[node] = column;

    final children = (g.outgoing[node] ?? const [])
        .where((c) => c.targetPort != 'loopback')
        .toList();

    // main - продолжение той же ветки; secondary - ответвление вправо
    final mains = children
        .where(
          (c) =>
              c.sourcePort == 'yes' ||
              c.sourcePort == 'out' ||
              c.sourcePort == 'body' ||
              c.sourcePort == 'in' ||
              c.sourcePort == 'exit',
        )
        .toList();
    final secondary = children.where((c) => c.sourcePort == 'no').toList();

    int maxCol = column;
    for (final c in mains) {
      final sub = _assignColumns(c.targetNodeName, column, g, cols);
      if (sub > maxCol) maxCol = sub;
    }
    for (final c in secondary) {
      final sub = _assignColumns(c.targetNodeName, maxCol + 1, g, cols);
      if (sub > maxCol) maxCol = sub;
    }
    return maxCol;
  }
}
