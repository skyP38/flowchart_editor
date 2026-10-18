import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../constants/diagram_constants.dart';
import '../domain/flowchart_graph.dart';
import '../domain/insertion_service.dart';
import '../domain/layout_engine.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';
import '../persistence/graph_mapper.dart';
import '../persistence/editor_state.dart';
import 'history_manager.dart';

class FlowController extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  FlowchartGraph _graph = FlowchartGraph.empty();
  Size _nodeSize = const Size(
    NodeConstants.defaultWidth,
    NodeConstants.defaultHeight,
  );
  bool _showGrid = true;
  double _scale = 1.0;
  bool _isToolbarVisible = true;

  late LayoutEngine _layoutEngine; // пересобирается при setNodeSize
  final InsertionService _insertion = InsertionService();
  final HistoryManager _history = HistoryManager(
    maxSize: HistoryConstants.maxHistorySize,
  );
  HistoryEntry _current() => HistoryEntry(_graph, _nodeSize);

  FlowController() {
    _layoutEngine = _buildEngine(_graph, _nodeSize);
  }

  static LayoutEngine _buildEngine(FlowchartGraph g, Size size) {
    final depth = LayoutEngine.maxForDepth(g);

    // горизонтальный шаг
    final baseExtraX = LayoutConstants.stepXExtra;
    double extraX = baseExtraX - 20;
    if (depth > 0) {
      const padding = LayoutConstants.loopbackChannelWidth;
      final ratio = 1.0 - (depth + 1) / 12.0;
      if (ratio > 0.1) {
        final requiredWidth = (size.width + padding) / ratio;
        final requiredExtra = requiredWidth - size.width;
        if (requiredExtra > extraX) extraX = requiredExtra;
      } else {
        // fallback на случай очень глубокой вложенности
        extraX = baseExtraX + depth * LayoutConstants.loopbackChannelWidth;
      }
    }
    // final extraX =
    //     LayoutConstants.stepXExtra +
    //     forDepth * LayoutConstants.loopbackChannelWidth;
    final extraY =
        LayoutConstants.stepYExtra +
        depth * LayoutConstants.loopbackChannelHeight;
    return LayoutEngine(
      nodeSize: size,
      spacing: LayoutSpacing(
        stepX: size.width + extraX,
        stepY: size.height + extraY,
      ),
    );
  }

  FlowchartGraph get graph => _graph;
  Map<String, NodeModel> get nodes => _graph.nodes;
  List<ConnectionData> get connections => _graph.connections;
  Size get nodeSize => _nodeSize;
  bool get showGrid => _showGrid;
  double get scale => _scale;
  bool get isToolbarVisible => _isToolbarVisible;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  LayoutSpacing get spacing => _layoutEngine.spacing;

  void initDefaultDiagram() {
    final start = NodeFactory.createNode(
      id: _uuid.v4(),
      data: const TerminalBlock('Start'),
      position: Offset(_nodeSize.height, _nodeSize.height),
    );
    final end = NodeFactory.createNode(
      id: _uuid.v4(),
      data: const TerminalBlock('End'),
      position: Offset(
        start.position.dx,
        start.position.dy + _nodeSize.height + LayoutConstants.startPadding,
      ),
    );

    var g = FlowchartGraph.empty().withNode(start).withNode(end);
    g = g.withConnection(
      ConnectionData(
        id: _uuid.v4(),
        sourceNodeName: start.name,
        sourcePort: 'out',
        targetNodeName: end.name,
        targetPort: 'in',
      ),
    );
    _graph = _relayout(g);
    notifyListeners();
  }

  // действия
  void insertNodeOnConnection(String connId, GostNodeData proto) {
    _pushHistory();
    final res = _insertion.insertOnConnection(_graph, connId, proto);
    _graph = _relayout(res.graph);
    notifyListeners();
  }

  void removeNode(String name) {
    final n = _graph.nodes[name];
    if (n == null) return;
    if (n.data is TerminalBlock &&
        (n.data.text == 'Start' || n.data.text == 'End')) {
      return;
    }
    _pushHistory();
    _graph = _relayout(_removeWithBridge(_graph, name));
    notifyListeners();
  }

  void removeConnection(String connectionId) {
    _pushHistory();
    _graph = _relayout(_graph.withoutConnection(connectionId));
    notifyListeners();
  }

  void updateNodeText(String name, String text) {
    final n = _graph.nodes[name];
    if (n == null) return;
    _pushHistory();
    _graph = _graph.withNode(n.copyWith(data: n.data.copyWith(text: text)));
    notifyListeners();
  }

  void updateNodePosition(String name, Offset position) {
    final n = _graph.nodes[name];
    if (n == null) return;
    _graph = _graph.withNode(n.copyWith(position: position));
    notifyListeners();
  }

  void setNodeSize(Size s) {
    if (_nodeSize == s) return;
    _pushHistory();
    _nodeSize = s;
    // _layoutEngine = LayoutEngine(
    //   nodeSize: s,
    //   spacing: LayoutSpacing(stepX: s.width + 70, stepY: s.height + 40),
    // );
    _graph = _relayout(_graph);
    notifyListeners();
  }

  void setShowGrid(bool value) {
    if (_showGrid == value) return;
    _showGrid = value;
    notifyListeners();
  }

  void setScale(double value) {
    if (_scale == value) return;
    _scale = value;
    notifyListeners();
  }

  void setToolbarVisible(bool value) {
    if (_isToolbarVisible == value) return;
    _isToolbarVisible = value;
    notifyListeners();
  }

  void undo() {
    final prev = _history.undo(_current());
    if (prev != null) {
      _graph = prev.graph;
      _nodeSize = prev.nodeSize;
      _layoutEngine = _buildEngine(_graph, _nodeSize);
      notifyListeners();
    }
  }

  void redo() {
    final next = _history.redo(_current());
    if (next != null) {
      _graph = next.graph;
      _nodeSize = next.nodeSize;
      _layoutEngine = _buildEngine(_graph, _nodeSize);
      notifyListeners();
    }
  }

  // сохранение
  EditorSnapshot toSnapshot() => GraphMapper.toSnapshot(
    graph: _graph,
    nodeWidth: _nodeSize.width,
    nodeHeight: _nodeSize.height,
    showGrid: _showGrid,
    scale: _scale,
    isToolbarVisible: _isToolbarVisible,
  );

  // загрузка
  void fromSnapshot(EditorSnapshot s) {
    _pushHistory(); // загрузку тоже можно отменить
    final restored = GraphMapper.fromSnapshot(s);

    _nodeSize = restored.nodeSize;

    _graph = _relayout(restored.graph); // пересчитываем раскладку из данных
    _showGrid = restored.showGrid;
    _scale = restored.scale;
    _isToolbarVisible = restored.isToolbarVisible;

    notifyListeners();
  }

  // helpers
  FlowchartGraph _relayout(FlowchartGraph g) {
    // final depth = LayoutEngine.maxForDepth(g);
    _layoutEngine = _buildEngine(g, _nodeSize);

    final positions = _layoutEngine.compute(g);
    final newNodes = <String, NodeModel>{};
    for (final e in g.nodes.entries) {
      final p = positions[e.key];
      newNodes[e.key] = p == null ? e.value : e.value.copyWith(position: p);
    }
    return FlowchartGraph(nodes: newNodes, connections: g.connections);
  }

  FlowchartGraph _removeWithBridge(FlowchartGraph g, String name) {
    final node = g.nodes[name];
    if (node == null) return g;
    if (node.data is TerminalBlock &&
        (node.data.text == 'Start' || node.data.text == 'End')) {
      return g;
    }

    final incoming = g.incoming[name] ?? const <ConnectionData>[];
    final outgoing = g.outgoing[name] ?? const <ConnectionData>[];

    final isLogic = node.data is LogicBlock;
    final isFor = node.data is ForBlock;

    final toRemove = <String>{name};
    if (isLogic) {
      final noConn = outgoing.firstWhereOrNull((c) => c.sourcePort == 'no');
      if (noConn != null) {
        toRemove.addAll(_collectSubtree(g, noConn.targetNodeName));
      }
    } else if (isFor) {
      final bodyConn = outgoing.firstWhereOrNull((c) => c.sourcePort == 'body');
      if (bodyConn != null) {
        toRemove.addAll(_collectSubtree(g, bodyConn.targetNodeName));
      }
    }
    toRemove.removeWhere(g.isEnd);

    final newNodes = Map<String, NodeModel>.from(g.nodes)
      ..removeWhere((k, _) => toRemove.contains(k));

    final newConns = g.connections
        .where(
          (c) =>
              !toRemove.contains(c.sourceNodeName) &&
              !toRemove.contains(c.targetNodeName),
        )
        .toList();

    final inConn = incoming.isNotEmpty ? incoming.first : null;
    ConnectionData? bridge;

    if (isLogic) {
      final yesConn = outgoing.firstWhereOrNull((c) => c.sourcePort == 'yes');
      if (inConn != null &&
          yesConn != null &&
          newNodes.containsKey(yesConn.targetNodeName)) {
        bridge = ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: inConn.sourceNodeName,
          sourcePort: inConn.sourcePort,
          targetNodeName: yesConn.targetNodeName,
          targetPort: yesConn.targetPort,
        );
      }
    } else if (isFor) {
      final exitConn = outgoing.firstWhereOrNull((c) => c.sourcePort == 'exit');
      if (inConn != null &&
          exitConn != null &&
          newNodes.containsKey(exitConn.targetNodeName)) {
        bridge = ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: inConn.sourceNodeName,
          sourcePort: inConn.sourcePort,
          targetNodeName: exitConn.targetNodeName,
          targetPort: exitConn.targetPort,
        );
      }
    } else {
      if (incoming.length == 1 && outgoing.length == 1) {
        final inC = incoming.first;
        final outC = outgoing.first;
        bridge = ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: inC.sourceNodeName,
          sourcePort: inC.sourcePort,
          targetNodeName: outC.targetNodeName,
          targetPort: outC.targetPort,
        );
      }
    }
    if (bridge != null) newConns.add(bridge);

    return FlowchartGraph(nodes: newNodes, connections: newConns);
  }

  Set<String> _collectSubtree(FlowchartGraph g, String start) {
    final result = <String>{};
    void dfs(String n) {
      if (result.contains(n) || g.isEnd(n)) return;
      result.add(n);
      for (final c in g.outgoing[n] ?? const <ConnectionData>[]) {
        if (c.targetPort == 'loopback') continue;
        dfs(c.targetNodeName);
      }
    }

    dfs(start);
    return result;
  }

  void _pushHistory() {
    _history.push(HistoryEntry(_graph, _nodeSize));
  }

  // Очищает undo/redo
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}
