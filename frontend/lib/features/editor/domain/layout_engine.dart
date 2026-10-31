import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/flow_models.dart';
import 'flowchart_graph.dart';
import 'dart:math' as math;
import '../models/editor_models.dart';

class LayoutSpacing {
  final double stepX;
  final double stepY;
  const LayoutSpacing({required this.stepX, required this.stepY});
}

// rank - длина самого длинного пути от Start (loopback игнорируется)
// column - номер ветки, out/yes/body - та же колонка;
// no/exit - новая колонка справа от всего, что занято main-поддеревом
class LayoutEngine {
  final Size nodeSize;
  final LayoutSpacing spacing;

  const LayoutEngine({required this.nodeSize, required this.spacing});

  Map<String, Offset> compute(FlowchartGraph g) {
    final start = g.findStart();
    if (start == null) return const {};

    // Ранги (Y)
    final ranks = <String, int>{};
    _assignRanks(start.name, 0, g, ranks, {});

    // Выход каждого For должен лежать ниже всего его тела
    _adjustForExitRanks(g, ranks);
    _pushMergeNodesForSpace(g, ranks);

    // End - на самом низком ранге
    _pushEndToBottom(g, ranks);
    _pushEndFeedersDown(g, ranks);
    _pushEndForMergeSpace(g, ranks);

    // Колонки (X)
    final cols = <String, int>{};

    // Main-линия: все узлы по основным ребрам получают колонку родителя
    _assignMainColumns(start.name, 0, g, cols);

    // level узла = минимальное число no-ребер на пути от Start
    // 0 - в main, 1 - внутри первой no-ветки, 2 - внутри no-ветки от no-ветки, и т.д.
    final nodeLevel = <String, int>{};
    void computeLevel(String n, int lvl) {
      if ((nodeLevel[n] ?? (1 << 30)) <= lvl) return;
      nodeLevel[n] = lvl;
      for (final c in g.outgoing[n] ?? const []) {
        if (c.targetPort == 'loopback') continue;
        computeLevel(c.targetNodeName, lvl + (c.sourcePort == 'no' ? 1 : 0));
      }
    }

    computeLevel(start.name, 0);

    // Кол-во yes от Start до каждого узла (максимум по всем путям)
    final yesDepth = <String, int>{};
    void computeYesDepth(String n, int d) {
      if (d > 100) return; // защита от циклов
      if ((yesDepth[n] ?? -1) >= d) return;
      yesDepth[n] = d;
      for (final c in g.outgoing[n] ?? const []) {
        if (c.targetPort == 'loopback') continue;
        computeYesDepth(c.targetNodeName, c.sourcePort == 'yes' ? d + 1 : d);
      }
    }

    computeYesDepth(start.name, 0);

    // Собираем все no-ветки с интервалами
    final branches = <_NoBranch>[];
    for (final e in g.nodes.entries) {
      final outs = g.outgoing[e.key] ?? const [];
      for (final c in outs) {
        if (c.sourcePort != 'no' || c.targetPort == 'loopback') continue;

        // rejoin: yes/out и no одного родителя ведут в один узел
        final sameTargetYes = outs.any(
          (o) =>
              (o.sourcePort == 'yes' || o.sourcePort == 'out') &&
              o.targetNodeName == c.targetNodeName,
        );
        if (sameTargetYes) continue;
        bool reachableFromYes = false;
        for (final o in outs) {
          if (o.sourcePort == 'yes' || o.sourcePort == 'out') {
            if (_reachableViaYesOut(g, o.targetNodeName, c.targetNodeName)) {
              reachableFromYes = true;
              break;
            }
          }
        }
        if (reachableFromYes) continue;

        final rEnd = _exitRankOf(g, c.targetNodeName, ranks, cols);
        branches.add(
          _NoBranch(
            branchName: c.targetNodeName,
            parentName: e.key,
            rStart: ranks[c.targetNodeName] ?? 0,
            rEnd: rEnd,
          ),
        );
      }
    }

    branches.sort((a, b) {
      final da = yesDepth[a.branchName] ?? 0;
      final db = yesDepth[b.branchName] ?? 0;
      final byDepth = db.compareTo(da); // DESC
      if (byDepth != 0) return byDepth;

      final la = nodeLevel[a.branchName] ?? 0;
      final lb = nodeLevel[b.branchName] ?? 0;
      final byLevel = la.compareTo(lb);
      if (byLevel != 0) return byLevel;
      return b.rStart.compareTo(a.rStart);
    });

    final placed = <_PlacedBranch>[];
    for (final nb in branches) {
      if (cols.containsKey(nb.branchName)) continue;
      final parentCol = _eventualCol(g, cols, nb.parentName);

      int col = parentCol + 1;
      while (placed.any(
        (p) => p.col == col && p.rStart <= nb.rEnd && p.rEnd >= nb.rStart,
      )) {
        col++;
      }

      cols[nb.branchName] = col;
      placed.add(_PlacedBranch(col: col, rStart: nb.rStart, rEnd: nb.rEnd));

      _assignBranchSubtree(
        nb.branchName,
        col,
        g,
        cols,
        <String>{},
        isRoot: true,
      );
    }

    // rejoin-узлы, у которых walk не установил колонку, берут max колонки source
    for (final name in g.nodes.keys) {
      if (cols.containsKey(name)) continue;
      if (g.isEnd(name)) continue;

      final incoming = (g.incoming[name] ?? const [])
          .where((c) => c.targetPort != 'loopback')
          .toList();
      if (incoming.isEmpty) continue;

      final mainIncoming = incoming
          .where(
            (c) =>
                c.sourcePort == 'yes' ||
                c.sourcePort == 'out' ||
                c.sourcePort == 'body' ||
                c.sourcePort == 'in',
          )
          .toList();

      if (mainIncoming.isNotEmpty) {
        cols[name] = mainIncoming
            .map((c) => cols[c.sourceNodeName] ?? 0)
            .reduce((a, b) => a < b ? a : b);
      } else {
        cols[name] = incoming
            .map((c) => cols[c.sourceNodeName] ?? 0)
            .reduce((a, b) => a > b ? a : b);
      }
    }

    // Сборка
    final result = <String, Offset>{};
    // Сдвиг для центровки блоков в ячейках сетки
    final shiftX = (spacing.stepX - nodeSize.width) / 2;
    final shiftY = (spacing.stepY - nodeSize.height) / 2;
    final depth = maxForDepth(g);
    final insetOuter = spacing.stepX / 12.0 * (depth + 1);
    const leftMargin = 20.0;
    final baseX = math.max(50.0, insetOuter - shiftX + leftMargin);

    const baseY = 50.0;
    for (final name in g.nodes.keys) {
      final r = ranks[name] ?? 0;
      final c = cols[name] ?? 0;
      result[name] = Offset(
        baseX + c * spacing.stepX + shiftX,
        baseY + r * spacing.stepY + shiftY,
      );
    }
    return result;
  }

  // Предсказывает колонку узла до фактического размещения его ветки
  int _eventualCol(
    FlowchartGraph g,
    Map<String, int> cols,
    String name, [
    Set<String>? visiting,
  ]) {
    final existing = cols[name];
    if (existing != null) return existing;

    visiting ??= <String>{};
    if (!visiting.add(name)) return 0; // защита от циклов

    final incoming = (g.incoming[name] ?? const <ConnectionData>[])
        .where((c) => c.targetPort != 'loopback')
        .toList();
    if (incoming.isEmpty) {
      visiting.remove(name);
      return 0;
    }

    int result;
    final noIn = incoming.firstWhereOrNull((c) => c.sourcePort == 'no');
    final yesIn = incoming.firstWhereOrNull((c) => c.sourcePort == 'yes');

    final isMergePair =
        noIn != null &&
        yesIn != null &&
        noIn.sourceNodeName == yesIn.sourceNodeName;

    if (noIn != null && !isMergePair) {
      result = _eventualCol(g, cols, noIn.sourceNodeName, visiting) + 1;
    } else {
      final mainIn = incoming.firstWhereOrNull(
        (c) =>
            c.sourcePort == 'yes' ||
            c.sourcePort == 'out' ||
            c.sourcePort == 'body' ||
            c.sourcePort == 'in',
      );
      if (mainIn != null) {
        result = _eventualCol(g, cols, mainIn.sourceNodeName, visiting);
      } else {
        // merge-узел — берём минимум по источникам
        result = incoming
            .map((c) => _eventualCol(g, cols, c.sourceNodeName, visiting))
            .reduce((a, b) => a < b ? a : b);
      }
    }

    visiting.remove(name);
    return result;
  }

  void _pushMergeNodesForSpace(FlowchartGraph g, Map<String, int> ranks) {
    bool changed = true;
    int iterations = 0;
    while (changed && iterations < 20) {
      changed = false;
      iterations++;
      final names = g.nodes.keys.toList()
        ..sort((a, b) => (ranks[a] ?? 0).compareTo(ranks[b] ?? 0));

      for (final name in names) {
        if (g.isEnd(name)) continue;
        final incoming = (g.incoming[name] ?? const <ConnectionData>[])
            .where((c) => c.targetPort != 'loopback')
            .toList();
        if (incoming.length < 2) continue;

        final sources = incoming.map((c) => c.sourceNodeName).toSet();
        final isOnlyTrivialRejoin =
            sources.length == 1 &&
            incoming.every(
              (c) => c.sourcePort == 'yes' || c.sourcePort == 'no',
            );
        if (isOnlyTrivialRejoin) continue;

        final sourceRanks =
            incoming.map((c) => ranks[c.sourceNodeName] ?? 0).toList()
              ..sort((a, b) => b.compareTo(a));

        final maxPredRank = sourceRanks.first;
        final minPredRank = sourceRanks.last;
        if (maxPredRank - minPredRank < 2) continue;

        final noCount = incoming.where((c) => c.sourcePort == 'no').length;
        final pairGap = spacing.stepX / 12;
        final neededCorridorSpace = noCount * 2 * pairGap;
        final extraRanks = neededCorridorSpace > spacing.stepY
            ? ((neededCorridorSpace - spacing.stepY) / spacing.stepY).ceil()
            : 0;

        final desired = maxPredRank + 2 + extraRanks;
        final current = ranks[name] ?? 0;
        if (current < desired) {
          final delta = desired - current;
          ranks[name] = desired;
          _pushDescendantsForSpace(g, name, delta, ranks);
          changed = true;
        }
      }
    }
  }

  // Сдвигает всех потомков name на delta рангов вниз
  void _pushDescendantsForSpace(
    FlowchartGraph g,
    String name,
    int delta,
    Map<String, int> ranks, {
    String? skipEnd,
  }) {
    final visited = <String>{name};
    final queue = <String>[];
    for (final c in g.outgoing[name] ?? const <ConnectionData>[]) {
      if (c.targetPort == 'loopback') continue;
      queue.add(c.targetNodeName);
    }
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (skipEnd != null && cur == skipEnd) continue;
      ranks[cur] = (ranks[cur] ?? 0) + delta;
      for (final c in g.outgoing[cur] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
  }

  // Достижим ли to из from по цепочке yes/out
  bool _reachableViaYesOut(FlowchartGraph g, String from, String to) {
    if (from == to) return true;
    final visited = <String>{from};
    final queue = <String>[from];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      for (final c in g.outgoing[cur] ?? const []) {
        if (c.sourcePort != 'yes' && c.sourcePort != 'out') continue;
        if (c.targetNodeName == to) return true;
        if (visited.add(c.targetNodeName)) queue.add(c.targetNodeName);
      }
    }
    return false;
  }

  // Проходит поддерево ветки, ставит всем потомкам ту же колонку
  // Останавливается на:
  // - End (всегда col 0);
  // - rejoin-узлах (несколько входов - принадлежат main);
  // - уже посещенных (защита от циклов).
  void _assignBranchSubtree(
    String node,
    int column,
    FlowchartGraph g,
    Map<String, int> cols,
    Set<String> visited, {
    required bool isRoot,
  }) {
    if (visited.contains(node)) return;
    if (g.isEnd(node)) return;
    visited.add(node);

    final incoming = (g.incoming[node] ?? const [])
        .where((c) => c.targetPort != 'loopback')
        .toList();

    // Rejoin = входы из разных узлов
    final distinctSources = incoming.map((c) => c.sourceNodeName).toSet();
    if (!isRoot && distinctSources.length > 1) return;

    cols[node] = column;

    for (final c in g.outgoing[node] ?? const []) {
      if (c.sourcePort == 'no') {
        continue; // вложенные no обрабатываются отдельно
      }
      if (c.targetPort == 'loopback') continue;

      _assignBranchSubtree(
        c.targetNodeName,
        column,
        g,
        cols,
        visited,
        isRoot: false,
      );
    }
  }

  void _assignRanks(
    String node,
    int rank,
    FlowchartGraph g,
    Map<String, int> ranks,
    Set<String> inProgress,
  ) {
    if ((ranks[node] ?? -1) >= rank) return;
    if (!inProgress.add(node)) {
      return;
    } // защита от циклов
    ranks[node] = rank;
    for (final c in g.outgoing[node] ?? const []) {
      if (c.targetPort == 'loopback') continue;

      final targetRank = ranks[c.targetNodeName];
      final isBackwardExit =
          c.sourcePort == 'exit' && targetRank != null && targetRank <= rank;
      if (isBackwardExit) continue;
      _assignRanks(c.targetNodeName, rank + 1, g, ranks, inProgress);
    }
    inProgress.remove(node);
  }

  // Для каждого For: exit-цель должна быть на ранг ниже, чем самый глубокий узел тела
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

      if (bodyConn.targetNodeName == forName) continue;

      final bodySubtree = _bodySubtreeNodes(g, bodyConn.targetNodeName);
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

  // Поддерево тела цикла: обходит body-ветку,
  Set<String> _bodySubtreeNodes(FlowchartGraph g, String root) {
    final result = <String>{};
    void dfs(String n) {
      if (result.contains(n)) return;
      result.add(n);
      if (g.isEnd(n)) return;
      for (final c in g.outgoing[n] ?? const []) {
        if (c.targetPort == 'loopback') continue;
        if (c.sourcePort == 'exit') continue; // не выходим за пределы тела
        dfs(c.targetNodeName);
      }
    }

    dfs(root);
    return result;
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

  void _pushEndFeedersDown(FlowchartGraph g, Map<String, int> ranks) {
    String? endName;
    for (final e in g.nodes.entries) {
      if (g.isEnd(e.key)) {
        endName = e.key;
        break;
      }
    }
    if (endName == null) return;

    // Найти все merge-точки, которые напрямую идут в End
    final mergeSources = <String>{};
    for (final c in g.connections) {
      if (c.targetNodeName != endName) continue;
      if (c.targetPort == 'loopback') continue;
      final sources = (g.incoming[c.sourceNodeName] ?? const <ConnectionData>[])
          .where((x) => x.targetPort != 'loopback')
          .map((x) => x.sourceNodeName)
          .toSet();
      if (sources.length >= 2) {
        mergeSources.add(c.sourceNodeName);
      }
    }
    if (mergeSources.isEmpty) return;

    final moving = <String>{};
    for (final s in mergeSources) {
      for (final c in g.outgoing[s] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        moving.addAll(_subtreeNodes(g, c.targetNodeName));
      }
    }

    // Самый глубокий rank среди обычных узлов
    int maxOther = 0;
    for (final e in ranks.entries) {
      if (e.key == endName) continue;
      if (mergeSources.contains(e.key)) continue;
      if (moving.contains(e.key)) continue;
      if (e.value > maxOther) maxOther = e.value;
    }

    final desiredMergeRank = maxOther + 1;
    for (final s in mergeSources) {
      final node = g.nodes[s];
      if (node == null) continue;
      final hasBody = (g.outgoing[s] ?? const []).any(
        (c) => c.sourcePort == 'body',
      );
      if (hasBody) continue;

      if ((ranks[s] ?? 0) < desiredMergeRank) {
        final delta = desiredMergeRank - (ranks[s] ?? 0);
        ranks[s] = desiredMergeRank;
        _pushDescendantsForSpace(g, s, delta, ranks, skipEnd: endName);
      }
    }
    // Пересчет End
    int maxPredRank = 0;
    for (final c in g.incoming[endName] ?? const <ConnectionData>[]) {
      if (c.targetPort == 'loopback') continue;
      final r = ranks[c.sourceNodeName] ?? 0;
      if (r > maxPredRank) maxPredRank = r;
    }
    final desiredEndRank = maxPredRank + 1;
    if ((ranks[endName] ?? 0) < desiredEndRank) {
      ranks[endName] = desiredEndRank;
    }
  }

  void _pushEndForMergeSpace(FlowchartGraph g, Map<String, int> ranks) {
    String? endName;
    for (final e in g.nodes.entries) {
      if (g.isEnd(e.key)) {
        endName = e.key;
        break;
      }
    }
    if (endName == null) return;

    final incoming = (g.incoming[endName] ?? const <ConnectionData>[])
        .where((c) => c.targetPort != 'loopback')
        .toList();
    if (incoming.length < 2) return;

    int maxPredRank = 0;
    for (final c in incoming) {
      final r = ranks[c.sourceNodeName] ?? 0;
      if (r > maxPredRank) maxPredRank = r;
    }

    final desired = maxPredRank + 2;
    if ((ranks[endName] ?? 0) < desired) {
      ranks[endName] = desired;
    }
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

  void _assignMainColumns(
    String node,
    int column,
    FlowchartGraph g,
    Map<String, int> cols,
  ) {
    if (cols.containsKey(node)) return;
    cols[node] = column;
    for (final c in g.outgoing[node] ?? const []) {
      if (c.sourcePort == 'no') continue; // no-ветки обрабатываются отдельно
      if (c.targetPort == 'loopback') continue;
      _assignMainColumns(c.targetNodeName, column, g, cols);
    }
  }

  int _exitRankOf(
    FlowchartGraph g,
    String branchName,
    Map<String, int> ranks,
    Map<String, int> cols,
  ) {
    final visited = <String>{};
    int maxRank = ranks[branchName] ?? 0;
    String cur = branchName;
    for (int i = 0; i < 256; i++) {
      if (!visited.add(cur)) break;
      if (g.isEnd(cur)) break;
      final outs = (g.outgoing[cur] ?? const [])
          .where((c) => c.sourcePort != 'no' && c.targetPort != 'loopback')
          .toList();
      if (outs.isEmpty) break;
      final next = outs.first.targetNodeName;

      final r = ranks[next] ?? 0;
      if (r > maxRank) maxRank = r;

      if (cols[next] == 0) break;
      cur = next;
    }
    return maxRank;
  }

  // Максимальная глубина вложенности среди всех For графа
  static int maxForDepth(FlowchartGraph g) {
    int maxDepth = 0;
    for (final e in g.nodes.entries) {
      if (e.value.data is! ForBlock) continue;
      final a = _forAncestorCount(g, e.key);
      if (a > maxDepth) maxDepth = a;
    }
    return maxDepth;
  }

  static int _forAncestorCount(FlowchartGraph g, String forName) {
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
        final sub = _subtreeNodesStatic(g, c.targetNodeName);
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

  static Set<String> _subtreeNodesStatic(FlowchartGraph g, String root) {
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
}

class _NoBranch {
  final String branchName;
  final String parentName;
  final int rStart;
  final int rEnd;
  int level = 1;
  _NoBranch({
    required this.branchName,
    required this.parentName,
    required this.rStart,
    required this.rEnd,
  });
}

class _PlacedBranch {
  final int col;
  final int rStart;
  final int rEnd;
  const _PlacedBranch({
    required this.col,
    required this.rStart,
    required this.rEnd,
  });
}
