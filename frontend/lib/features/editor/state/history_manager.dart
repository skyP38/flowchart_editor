import 'package:flutter/material.dart';
import '../constants/diagram_constants.dart';

import '../domain/flowchart_graph.dart';

// Снапшот состояния: граф + размер блоков
class HistoryEntry {
  final FlowchartGraph graph;
  final Size nodeSize;
  const HistoryEntry(this.graph, this.nodeSize);
}

// Стек undo/redo над иммутабельными снапшотами графа
class HistoryManager {
  final int maxSize;
  final _undo = <HistoryEntry>[];
  final _redo = <HistoryEntry>[];
  HistoryManager({this.maxSize = HistoryConstants.maxHistorySize});

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // текущее состояние перед изменением
  void push(HistoryEntry g) {
    _undo.add(g);
    if (_undo.length > maxSize) _undo.removeAt(0);
    _redo.clear();
  }

  HistoryEntry? undo(HistoryEntry current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    if (_redo.length > maxSize) _redo.removeAt(0);
    return _undo.removeLast();
  }

  HistoryEntry? redo(HistoryEntry current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    if (_undo.length > maxSize) _undo.removeAt(0);
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
