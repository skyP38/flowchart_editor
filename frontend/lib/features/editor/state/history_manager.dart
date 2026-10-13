import 'package:flowchart_editor_frontend/features/editor/constants/diagram_constants.dart';

import '../domain/flowchart_graph.dart';

// Стек undo/redo над иммутабельными снапшотами графа
class HistoryManager {
  final int maxSize;
  final _undo = <FlowchartGraph>[];
  final _redo = <FlowchartGraph>[];
  HistoryManager({this.maxSize = HistoryConstants.maxHistorySize});

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // текущее состояние перед изменением
  void push(FlowchartGraph g) {
    _undo.add(g);
    if (_undo.length > maxSize) _undo.removeAt(0);
    _redo.clear();
  }

  FlowchartGraph? undo(FlowchartGraph current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    if (_redo.length > maxSize) _redo.removeAt(0);
    return _undo.removeLast();
  }

  FlowchartGraph? redo(FlowchartGraph current) {
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
