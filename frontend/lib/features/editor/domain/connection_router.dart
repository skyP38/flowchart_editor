import 'package:flutter/material.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';
import 'flowchart_graph.dart';
import 'layout_engine.dart';

class ConnectionRouter {
  final Size nodeSize;
  final LayoutSpacing spacing;

  const ConnectionRouter({required this.nodeSize, required this.spacing});

  Path build(ConnectionData conn, FlowchartGraph g) {
    final source = g.nodes[conn.sourceNodeName];
    final target = g.nodes[conn.targetNodeName];
    if (source == null || target == null) return Path();

    final start = _portPosition(source, conn.sourcePort, outgoing: true);
    final end = _portPosition(target, conn.targetPort, outgoing: false);

    if (conn.targetPort == 'loopback') {
      return _routeLoopback(start, end, g, conn);
    }

    return switch (conn.sourcePort) {
      'no' => _routeNo(start, end, g, conn),
      'yes' => _routeYes(start, end, g, conn),
      'body' => _routeBody(start, end, g, conn),
      'exit' => _routeExit(start, end, g, conn),
      _ => _routeDefault(start, end, g, conn),
    };
  }

  // Позиция порта в координатах холста
  Offset _portPosition(NodeModel n, String port, {required bool outgoing}) {
    final p = n.position;
    final w = nodeSize.width;
    final h = nodeSize.height;

    switch (port) {
      // Точка входа любого блока
      case 'in':
        return p + Offset(w / 2, 0);

      // Выходы, идущие вниз по «главной» ветке
      case 'out':
      case 'yes':
      case 'body':
        return p + Offset(w / 2, h);

      // Выходы, идущие вправо
      case 'no':
      case 'exit':
        return p + Offset(w, h / 2);

      // Обратная связь тела цикла к For
      case 'loopback':
        return outgoing ? p + Offset(w / 2, h) : p + Offset(0, h / 2);

      // Fallback: по направлению ребра
      default:
        return outgoing ? p + Offset(w / 2, h) : p + Offset(w / 2, 0);
    }
  }

  //  маршруты
  // Обычный выход/yes: вертикально вниз
  Path _routeDefault(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final path = Path()..moveTo(start.dx, start.dy);
    if ((start.dx - end.dx).abs() < 0.5) {
      path.lineTo(end.dx, end.dy);
      return path;
    }

    // Разные колонки. Нужно выбрать Y, на котором горизонтальный сдвиг
    // и последующий спуск в целевую колонку не пересекут ни одного блока.
    final minX = start.dx < end.dx ? start.dx : end.dx;
    final maxX = start.dx < end.dx ? end.dx : start.dx;

    double maxBottom = start.dy;
    for (final e in g.nodes.entries) {
      if (e.key == c.targetNodeName) continue;
      final n = e.value;
      final left = n.position.dx;
      final right = n.position.dx + nodeSize.width;

      // Блок должен пересекаться с горизонтальным коридором
      if (right < minX || left > maxX) continue;
      // Блоки на уровне цели или ниже — не мешают
      if (n.position.dy >= end.dy - 1.0) continue;

      final bottom = n.position.dy + nodeSize.height;
      // Блоки целиком выше стартового порта — тоже не мешают
      if (bottom <= start.dy) continue;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    final desired = maxBottom + spacing.stepY / 4;

    // final local = _subtreeBounds(g, c.sourceNodeName, stopAt: c.targetNodeName);
    // final desired = local.bottom + spacing.stepY / 8;
    final cap = end.dy - spacing.stepY / 8;
    final midY = desired < cap ? desired : cap;
    path
      ..lineTo(start.dx, midY)
      ..lineTo(end.dx, midY)
      ..lineTo(end.dx, end.dy);

    return path;
  }

  Path _routeYes(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) => _routeDefault(start, end, g, c);

  Path _routeBody(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) => _routeDefault(start, end, g, c);

  // no: из правого порта -> вниз на уровень цели -> горизонталь -> вниз
  Path _routeNo(Offset start, Offset end, FlowchartGraph g, ConnectionData c) {
    final path = Path()..moveTo(start.dx, start.dy);
    final targetIsLeft = end.dx < start.dx - 1.0;

    if (!targetIsLeft) {
      // Цель справа: обычный L-путь — вправо до оси цели и вниз
      path
        ..lineTo(end.dx, start.dy)
        ..lineTo(end.dx, end.dy);
      return path;
    }

    final minX = end.dx < start.dx ? end.dx : start.dx;
    final maxX = end.dx < start.dx ? start.dx : end.dx;

    // Нижняя граница - только по блокам, реально стоящим на пути канала
    double maxBottom = start.dy;
    for (final e in g.nodes.entries) {
      if (e.key == c.targetNodeName) continue;
      final n = e.value;
      final left = n.position.dx;
      final right = n.position.dx + nodeSize.width;
      if (right < minX || left > maxX) continue;
      if (n.position.dy >= end.dy - 1.0) continue;
      final bottom = n.position.dy + nodeSize.height;
      if (bottom > maxBottom) maxBottom = bottom;
    }

    final channelY = maxBottom + spacing.stepY / 4;
    final stepXExtra = spacing.stepX - nodeSize.width;
    final rightX = start.dx + stepXExtra / 2;
    path
      ..lineTo(rightX, start.dy) // вправо в зазор
      ..lineTo(rightX, channelY) // вниз в канал
      ..lineTo(end.dx, channelY) // влево по каналу
      ..lineTo(end.dx, end.dy); // вверх/вниз в верхний порт цели

    return path;
  }

  // exit: из правого порта For, обходим тело цикла справа и снизу
  Path _routeExit(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final bas = spacing.stepX / 6;
    // Локальные границы тела этого For
    final local = _subtreeBounds(g, c.sourceNodeName, stopAt: c.targetNodeName);
    // Глубина: сколько For-предков у данного источника
    final ancestors = _forAncestorCount(g, c.sourceNodeName);
    final maxDepth = LayoutEngine.maxForDepth(g);
    final levelsFromInner = maxDepth - ancestors;

    // Правый коридор
    // для вложенных - каждый следующий сдвигается на base
    final rightX = local.right + bas / 2 * (levelsFromInner + 1);

    final depthOffset = spacing.stepY / 6 * levelsFromInner;
    final desired = local.bottom + spacing.stepY / 4 + depthOffset;
    final cap = end.dy - spacing.stepY / 8;
    final turnY = desired < cap ? desired : cap;

    // Цель правее правого края - обходить нечего
    if (end.dx >= rightX) {
      return Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, start.dy)
        ..lineTo(end.dx, end.dy);
    }

    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(rightX, start.dy)
      ..lineTo(rightX, turnY)
      ..lineTo(end.dx, turnY)
      ..lineTo(end.dx, end.dy);
  }

  // loopback: из низа тела цикла -> влево -> вверх -> в левый порт For
  Path _routeLoopback(
    Offset start,
    Offset end,
    FlowchartGraph g,
    ConnectionData c,
  ) {
    final bas = spacing.stepX / 6;

    final ancestors = _forAncestorCount(g, c.targetNodeName);
    final maxDepth = LayoutEngine.maxForDepth(g);
    final levelsFromInner = maxDepth - ancestors; // 0 у самого внутреннего
    final inset = bas / 2 * (levelsFromInner + 1);
    // final gap = spacing.stepX / 6;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx, start.dy + bas / 3)
      ..lineTo(end.dx - inset, start.dy + bas / 3)
      ..lineTo(end.dx - inset, end.dy)
      ..lineTo(end.dx, end.dy);
  }

  // Сколько For-предков имеет forName
  // 0 - внешний цикл, 1 - вложенный в него, и т.д.
  int _forAncestorCount(FlowchartGraph g, String forName) {
    int count = 0;
    String cur = forName;
    final visited = <String>{forName};

    while (true) {
      String? bestParent;
      int bestSize = 1 << 30;

      for (final c in g.connections) {
        if (c.sourcePort != 'body') continue;
        if (visited.contains(c.sourceNodeName)) continue;

        // Прямой предок
        if (c.targetNodeName == cur) {
          bestParent = c.sourceNodeName;
          bestSize = 0;
          break;
        }

        // Косвенный - только если он ближайший (минимальное поддерево)
        final sub = _subtreeNodes(g, c.targetNodeName);
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

  // Все узлы, достижимые из root по обычным ребрам (без loopback)
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

  // Нижняя и правая границы поддерева, начиная с rootName
  ({double bottom, double right}) _subtreeBounds(
    FlowchartGraph g,
    String rootName, {
    required String stopAt,
  }) {
    final stepXExtra = spacing.stepX - nodeSize.width;
    double bottom = -double.infinity;
    double right = -double.infinity;
    final visited = <String>{};
    final queue = <String>[rootName];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (!visited.add(cur)) continue;
      if (cur == stopAt) continue;
      final n = g.nodes[cur];
      if (n == null) continue;

      final b = n.position.dy + nodeSize.height;
      double r = n.position.dx + nodeSize.width;

      // Габарит по X: правый край + коридор исходящей no-ветки.
      final children = g.outgoing[cur] ?? const [];
      final hasNo = children.any(
        (c) => c.sourcePort == 'no' && c.targetNodeName != stopAt,
      );
      if (hasNo) r += stepXExtra / 2;

      if (b > bottom) bottom = b;
      if (r > right) right = r;

      for (final c in children) {
        if (c.targetPort == 'loopback') continue;
        queue.add(c.targetNodeName);
      }
    }
    return (bottom: bottom, right: right);
  }
}
