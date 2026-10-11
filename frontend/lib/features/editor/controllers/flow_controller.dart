import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import '../models/editor_state.dart';
import '../models/flow_models.dart';

/// Контроллер состояния блок-схемы
class FlowController extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  final Map<String, NodeWidgetData> _nodes = {};
  final List<ConnectionData> _connections = [];

  Size _nodeSize = const Size(160, 80);
  bool _showGrid = true;
  double _scale = 1.0;
  bool _isToolbarVisible = true;

  static const int _maxHistorySize = 50;
  final List<EditorSnapshot> _undoStack = [];
  final List<EditorSnapshot> _redoStack = [];
  bool _isUndoRedoOperation = false;

  Map<String, NodeWidgetData> get nodes => Map.unmodifiable(_nodes);
  List<ConnectionData> get connections => List.unmodifiable(_connections);

  Size get nodeSize => _nodeSize;
  bool get showGrid => _showGrid;
  double get scale => _scale;
  bool get isToolbarVisible => _isToolbarVisible;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // Добавляет узел без записи в историю
  void addNodeSilently(NodeModel node) {
    _nodes[node.name] = NodeWidgetData(node: node);
  }

  // Публичное добавление узла - записывает в историю
  void addNode(NodeModel node) {
    _pushState();
    addNodeSilently(node);
    _performAutoLayout();
    notifyListeners();
  }

  // Удаляет узел
  bool removeNode(String nodeName) {
    final removed = _nodes[nodeName]?.node;
    if (removed == null) return false;

    if (removed.data is TerminalBlock) {
      final text = removed.data.text;
      if (text == 'Start' || text == 'End') return false;
    }

    _pushState();

    final incoming = _connections
        .where((c) => c.targetNodeName == nodeName)
        .toList();
    final outgoing = _connections
        .where((c) => c.sourceNodeName == nodeName)
        .toList();
    final isLogic = removed.data is LogicBlock;
    final isFor = removed.data is ForBlock;

    if (isLogic) {
      _removeLogicBlock(nodeName, incoming, outgoing);
    } else if (isFor) {
      _removeForBlock(nodeName, incoming, outgoing);
    } else {
      _removePlainBlock(nodeName, incoming, outgoing);
    }

    _performAutoLayout();
    notifyListeners();
    return true;
  }

  void _removeLogicBlock(
    String nodeName,
    List<ConnectionData> incoming,
    List<ConnectionData> outgoing,
  ) {
    final incomingConn = incoming.isNotEmpty ? incoming.first : null;
    final outgoingYes = outgoing.firstWhereOrNull((c) => c.sourcePort == 'yes');
    final outgoingNo = outgoing.firstWhereOrNull((c) => c.sourcePort == 'no');

    final Set<String> nodesToRemove = {nodeName};
    if (outgoingNo != null) {
      _collectSubtreeExcludingEnd(outgoingNo.targetNodeName, nodesToRemove);
    }
    for (final n in nodesToRemove) {
      if (n == nodeName) continue;
      final node = _nodes[n]?.node;
      if (node != null &&
          node.data is TerminalBlock &&
          node.data.text == 'End') {
        continue;
      }
      _nodes.remove(n);
    }

    final nodesToRemoveFinal = nodesToRemove.where((n) {
      final nd = _nodes[n]?.node;
      return !(nd != null && nd.data is TerminalBlock && nd.data.text == 'End');
    }).toSet();
    nodesToRemoveFinal.add(nodeName);

    _connections.removeWhere(
      (c) =>
          nodesToRemoveFinal.contains(c.sourceNodeName) ||
          nodesToRemoveFinal.contains(c.targetNodeName),
    );

    if (incomingConn != null &&
        outgoingYes != null &&
        _nodes.containsKey(outgoingYes.targetNodeName)) {
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: incomingConn.sourceNodeName,
          sourcePort: incomingConn.sourcePort,
          targetNodeName: outgoingYes.targetNodeName,
          targetPort: outgoingYes.targetPort,
        ),
      );
    }
    _nodes.remove(nodeName);
  }

  void _removeForBlock(
    String nodeName,
    List<ConnectionData> incoming,
    List<ConnectionData> outgoing,
  ) {
    final incomingConn = incoming.isNotEmpty ? incoming.first : null;
    final outgoingExit = outgoing.firstWhereOrNull(
      (c) => c.sourcePort == 'exit',
    );
    final outgoingBody = outgoing.firstWhereOrNull(
      (c) => c.sourcePort == 'body',
    );

    final Set<String> nodesToRemove = {nodeName};
    if (outgoingBody != null) {
      _collectSubtreeExcludingEnd(outgoingBody.targetNodeName, nodesToRemove);
    }
    for (final n in nodesToRemove) {
      if (n == nodeName) continue;
      final node = _nodes[n]?.node;
      if (node != null &&
          node.data is TerminalBlock &&
          node.data.text == 'End') {
        continue;
      }
      _nodes.remove(n);
    }

    final nodesToRemoveFinal = nodesToRemove.where((n) {
      final nd = _nodes[n]?.node;
      return !(nd != null && nd.data is TerminalBlock && nd.data.text == 'End');
    }).toSet();
    nodesToRemoveFinal.add(nodeName);

    _connections.removeWhere(
      (c) =>
          nodesToRemoveFinal.contains(c.sourceNodeName) ||
          nodesToRemoveFinal.contains(c.targetNodeName),
    );

    if (incomingConn != null &&
        outgoingExit != null &&
        _nodes.containsKey(outgoingExit.targetNodeName)) {
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: incomingConn.sourceNodeName,
          sourcePort: incomingConn.sourcePort,
          targetNodeName: outgoingExit.targetNodeName,
          targetPort: outgoingExit.targetPort,
        ),
      );
    }
    _nodes.remove(nodeName);
  }

  void _removePlainBlock(
    String nodeName,
    List<ConnectionData> incoming,
    List<ConnectionData> outgoing,
  ) {
    if (incoming.length == 1 && outgoing.length == 1) {
      final inConn = incoming.first;
      final outConn = outgoing.first;
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: inConn.sourceNodeName,
          sourcePort: inConn.sourcePort,
          targetNodeName: outConn.targetNodeName,
          targetPort: outConn.targetPort,
        ),
      );
    }
    _connections.removeWhere(
      (c) => c.sourceNodeName == nodeName || c.targetNodeName == nodeName,
    );
    _nodes.remove(nodeName);
  }

  // Пересчитывает точки вставки - маленькие кружки на связях,
  // по клику на которые можно вставить новый блок
  void updateNodePosition(String nodeName, Offset newPosition) {
    if (_nodes.containsKey(nodeName)) {
      _nodes[nodeName]!.position = newPosition;
      notifyListeners();
    }
  }

  void updateNodeText(String nodeName, String newText) {
    final node = _nodes[nodeName]?.node;
    if (node == null) return;
    _pushState();
    node.data = node.data.copyWith(text: newText);
    _performAutoLayout();
    notifyListeners();
  }

  void addConnection(ConnectionData conn) {
    if (_connections.any(
      (c) =>
          c.sourceNodeName == conn.sourceNodeName &&
          c.sourcePort == conn.sourcePort &&
          c.targetNodeName == conn.targetNodeName &&
          c.targetPort == conn.targetPort,
    )) {
      return;
    }
    _pushState();
    _connections.add(conn);
    _performAutoLayout();
    notifyListeners();
  }

  void removeConnection(String connectionId) {
    _pushState();
    _connections.removeWhere((c) => c.id == connectionId);
    _performAutoLayout();
    notifyListeners();
  }

  // Вставка в разрыв связи
  void insertNodeOnConnection(
    ConnectionData connection,
    GostNodeData prototype, {
    Offset? insertPosition,
  }) {
    final sourceNode = _nodes[connection.sourceNodeName]?.node;
    final targetNode = _nodes[connection.targetNodeName]?.node;
    if (sourceNode == null || targetNode == null) return;

    _pushState();

    // Позиция нового блока
    Offset newPos;
    if (connection.sourcePort == 'exit') {
      final sourceWidget = _nodes[connection.sourceNodeName]!;
      newPos = Offset(
        sourceWidget.position.dx + _nodeSize.width + 40,
        sourceWidget.position.dy,
      );
    } else if (insertPosition != null) {
      newPos = insertPosition;
    } else {
      final sourcePos = sourceNode.position;
      final targetPos = targetNode.position;
      newPos = Offset(
        (sourcePos.dx + targetPos.dx) / 2,
        (sourcePos.dy + targetPos.dy) / 2,
      );
    }

    final newNode = NodeFactory.createNode(
      id: _uuid.v4(),
      data: prototype,
      position: newPos,
    );
    addNodeSilently(newNode);

    // Удаляем исходную связь
    _connections.removeWhere((c) => c.id == connection.id);

    // source -> newNode
    _connections.add(
      ConnectionData(
        id: _uuid.v4(),
        sourceNodeName: connection.sourceNodeName,
        sourcePort: connection.sourcePort,
        targetNodeName: newNode.name,
        targetPort: 'in',
      ),
    );

    if (prototype is LogicBlock) {
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'yes',
          targetNodeName: connection.targetNodeName,
          targetPort: connection.targetPort,
        ),
      );

      // Найти или создать End
      NodeModel? endNode = _nodes.values
          .firstWhereOrNull(
            (w) => w.node.data is TerminalBlock && w.node.data.text == 'End',
          )
          ?.node;
      if (endNode == null) {
        final endPos = Offset(
          newPos.dx + _nodeSize.width + 80,
          newPos.dy + _nodeSize.height + 30,
        );
        endNode = NodeFactory.createNode(
          id: _uuid.v4(),
          data: TerminalBlock('End'),
          position: endPos,
        );
        addNodeSilently(endNode);
      }

      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'no',
          targetNodeName: endNode.name,
          targetPort: 'in',
        ),
      );
    } else if (prototype is ForBlock) {
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'exit',
          targetNodeName: connection.targetNodeName,
          targetPort: connection.targetPort,
        ),
      );

      final bodyPos = Offset(newPos.dx, newPos.dy + _nodeSize.height + 30);
      final bodyNode = NodeFactory.createNode(
        id: _uuid.v4(),
        data: ProcessBlock('Тело цикла'),
        position: bodyPos,
      );
      addNodeSilently(bodyNode);

      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'body',
          targetNodeName: bodyNode.name,
          targetPort: 'in',
        ),
      );
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: bodyNode.name,
          sourcePort: 'out',
          targetNodeName: newNode.name,
          targetPort: 'loopback',
        ),
      );
    } else {
      _connections.add(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'out',
          targetNodeName: connection.targetNodeName,
          targetPort: connection.targetPort,
        ),
      );
    }

    _performAutoLayout();
    notifyListeners();
  }

  // Устанавливает новый размер блоков и перестраивает раскладку

  void setNodeSize(Size newSize) {
    if (_nodeSize == newSize) return;
    _pushState();
    _nodeSize = newSize;
    _performAutoLayout();
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

  // Кладет текущее состояние в стек undo и очищает redo
  void _pushState() {
    if (_isUndoRedoOperation) return;
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _maxHistorySize) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  // Отмена последнего действия

  void undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    _redoStack.add(_captureSnapshot());
    if (_redoStack.length > _maxHistorySize) _redoStack.removeAt(0);
    _restoreSnapshot(previous);
    notifyListeners();
  }

  // Возврат отмененного действия
  void redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _maxHistorySize) _undoStack.removeAt(0);
    _restoreSnapshot(next);
    notifyListeners();
  }

  // Создает снимок текущего состояния редактора для истории/сохранения
  EditorSnapshot _captureSnapshot() {
    final nodesList = _nodes.entries
        .map((e) => SerializableNode.fromNode(e.value.node))
        .toList();
    final connectionsList = _connections
        .map((c) => SerializableConnection.fromConnection(c))
        .toList();
    return EditorSnapshot(
      nodes: nodesList,
      connections: connectionsList,
      nodeWidth: _nodeSize.width,
      nodeHeight: _nodeSize.height,
      showGrid: _showGrid,
      scale: _scale,
      isToolbarVisible: _isToolbarVisible,
    );
  }

  // Восстанавливает состояние редактора из снимка

  void _restoreSnapshot(EditorSnapshot snapshot) {
    _isUndoRedoOperation = true;

    _nodes.clear();
    for (final sn in snapshot.nodes) {
      final node = sn.toNode();
      _nodes[node.name] = NodeWidgetData(node: node);
    }
    _connections.clear();
    _connections.addAll(snapshot.connections.map((c) => c.toConnection()));

    _nodeSize = Size(snapshot.nodeWidth, snapshot.nodeHeight);
    _showGrid = snapshot.showGrid;
    _scale = snapshot.scale;
    _isToolbarVisible = snapshot.isToolbarVisible;

    _performAutoLayout();
    _isUndoRedoOperation = false;
  }

  // Снимок для сохранения в JSON
  EditorSnapshot toSnapshot() => _captureSnapshot();

  // Загружает состояние из JSON-снимка
  void fromSnapshot(EditorSnapshot snapshot) {
    _pushState();
    _restoreSnapshot(snapshot);
    notifyListeners();
  }

  // Устанавливает стартовую схему Start -> End
  void initDefaultDiagram() {
    _nodes.clear();
    _connections.clear();

    final startPos = Offset(_nodeSize.height, _nodeSize.height);
    final start = NodeFactory.createNode(
      id: _uuid.v4(),
      data: TerminalBlock('Start'),
      position: startPos,
    );
    addNodeSilently(start);

    final end = NodeFactory.createNode(
      id: _uuid.v4(),
      data: TerminalBlock('End'),
      position: Offset(startPos.dx, startPos.dy + _nodeSize.height + 50),
    );
    addNodeSilently(end);

    _connections.add(
      ConnectionData(
        id: _uuid.v4(),
        sourceNodeName: start.name,
        sourcePort: 'out',
        targetNodeName: end.name,
        targetPort: 'in',
      ),
    );

    notifyListeners();
  }

  void _performAutoLayout() {
    final startEntry = _nodes.entries.firstWhereOrNull(
      (e) =>
          e.value.node.data is TerminalBlock &&
          e.value.node.data.text == 'Start',
    );
    if (startEntry == null) return;

    final startName = startEntry.key;
    final startPos = startEntry.value.position;

    final double stepX = _nodeSize.width + 70.0;
    final double stepY = _nodeSize.height + 40.0;

    // Исходящие (loopback игнорируем)
    final Map<String, List<ConnectionData>> outgoing = {};
    for (final conn in _connections) {
      if (conn.targetPort == 'loopback') continue;
      outgoing.putIfAbsent(conn.sourceNodeName, () => []).add(conn);
    }

    // BFS - ранги
    final Map<String, int> ranks = {startName: 0};
    final queue = <String>[startName];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentRank = ranks[current]!;
      for (final conn in outgoing[current] ?? []) {
        final target = conn.targetNodeName;
        final newRank = currentRank + 1;
        if ((ranks[target] ?? -1) < newRank) {
          ranks[target] = newRank;
          queue.add(target);
        }
      }
    }

    // Рекурсивное распределение X
    final Map<String, double> xPositions = {};
    double layoutX(String nodeName, double currentX, Set<String> visited) {
      if (visited.contains(nodeName)) return currentX;
      visited.add(nodeName);

      if (!xPositions.containsKey(nodeName)) {
        xPositions[nodeName] = currentX;
      } else {
        currentX = xPositions[nodeName]!;
      }

      final children = outgoing[nodeName] ?? [];
      if (children.isEmpty) return currentX;

      final node = _nodes[nodeName]?.node;
      final isLogic = node?.data is LogicBlock;
      final isFor = node?.data is ForBlock;

      if ((isLogic || isFor) && children.length >= 2) {
        ConnectionData? main, secondary;
        for (final c in children) {
          if (c.sourcePort == 'yes' || c.sourcePort == 'exit') main = c;
          if (c.sourcePort == 'no' || c.sourcePort == 'body') secondary = c;
        }
        if (main != null) {
          layoutX(main.targetNodeName, currentX, visited);
        }
        if (secondary != null) {
          final targetNode = _nodes[secondary.targetNodeName]?.node;
          final isEnd =
              targetNode != null &&
              targetNode.data is TerminalBlock &&
              targetNode.data.text == 'End';
          double offset = secondary.sourcePort == 'body' ? 0 : stepX;
          layoutX(
            secondary.targetNodeName,
            currentX + (isEnd ? 0 : offset),
            visited,
          );
        }
      } else {
        for (final conn in children) {
          layoutX(conn.targetNodeName, currentX, visited);
        }
      }
      return currentX;
    }

    final visited = <String>{};
    layoutX(startName, startPos.dx, visited);

    // Коррекция перекрытий по рангам
    final Map<int, List<String>> nodesByRank = {};
    for (final e in ranks.entries) {
      nodesByRank.putIfAbsent(e.value, () => []).add(e.key);
    }
    const double gap = 50.0;
    for (final rank in nodesByRank.keys) {
      final names = nodesByRank[rank]!;
      names.sort((a, b) => xPositions[a]!.compareTo(xPositions[b]!));
      double nextMinX = startPos.dx;
      for (final name in names) {
        double cx = xPositions[name]!;
        if (cx < nextMinX) {
          cx = nextMinX;
          xPositions[name] = cx;
        }
        nextMinX = cx + _nodeSize.width + gap;
      }
    }

    // Тело цикла выравниваем по X блока For
    for (final conn in _connections) {
      if (conn.sourcePort == 'body') {
        final forX = xPositions[conn.sourceNodeName];
        if (forX != null && xPositions.containsKey(conn.targetNodeName)) {
          xPositions[conn.targetNodeName] = forX;
        }
      }
    }

    final Map<String, String> bodyRoots = {};
    for (final conn in _connections) {
      if (conn.sourcePort == 'body') {
        bodyRoots[conn.targetNodeName] = conn.sourceNodeName;
      }
    }
    for (final e in bodyRoots.entries) {
      final bodyRoot = e.key;
      final forNode = e.value;
      final forX = xPositions[forNode];
      if (forX == null) continue;
      final Set<String> subtree = {};
      _collectSubtreeExcludingEnd(bodyRoot, subtree);
      for (final n in subtree) {
        if (xPositions.containsKey(n)) xPositions[n] = forX;
      }
    }

    // Ветка exit - сдвиг вправо
    final Map<String, Set<String>> exitSubtrees = {};
    for (final conn in _connections) {
      if (conn.sourcePort == 'exit') {
        final Set<String> subtree = {};
        _collectSubtreeExcludingEnd(conn.targetNodeName, subtree);
        exitSubtrees[conn.sourceNodeName] = subtree;
      }
    }
    for (final e in exitSubtrees.entries) {
      final forNode = e.key;
      final subtree = e.value;
      final forX = xPositions[forNode];
      if (forX == null) continue;
      for (final n in subtree) {
        if (xPositions.containsKey(n)) xPositions[n] = forX + stepX;
      }
    }

    // Y-координаты
    final Map<String, Offset> newPositions = {};
    for (final e in ranks.entries) {
      final name = e.key;
      final rank = e.value;
      final x = xPositions[name] ?? startPos.dx;
      final y = startPos.dy + rank * stepY;
      newPositions[name] = Offset(x, y);
    }

    // End - ниже самого нижнего
    final endEntry = _nodes.entries.firstWhereOrNull(
      (e) =>
          e.value.node.data is TerminalBlock && e.value.node.data.text == 'End',
    );
    if (endEntry != null) {
      double maxY = startPos.dy;
      for (final e in newPositions.entries) {
        if (e.key == endEntry.key) continue;
        if (e.value.dy > maxY) maxY = e.value.dy;
      }
      newPositions[endEntry.key] = Offset(startPos.dx, maxY + stepY);
    }

    for (final e in newPositions.entries) {
      final widgetData = _nodes[e.key];
      if (widgetData != null) widgetData.position = e.value;
    }
  }

  void _collectSubtreeExcludingEnd(String start, Set<String> collected) {
    if (collected.contains(start)) return;
    final node = _nodes[start]?.node;
    if (node != null && node.data is TerminalBlock && node.data.text == 'End') {
      return;
    }
    collected.add(start);
    final children = _connections
        .where((c) => c.sourceNodeName == start && c.targetPort != 'loopback')
        .toList();
    for (final child in children) {
      _collectSubtreeExcludingEnd(child.targetNodeName, collected);
    }
  }
}
