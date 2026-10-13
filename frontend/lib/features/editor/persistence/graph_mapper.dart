import 'package:flutter/material.dart';
import '../domain/flowchart_graph.dart';
import '../factories/node_factory.dart';
import '../persistence/editor_state.dart';

class GraphMapper {
  GraphMapper._();

  // FlowchartGraph + настройки вида -> EditorSnapshot
  static EditorSnapshot toSnapshot({
    required FlowchartGraph graph,
    required double nodeWidth,
    required double nodeHeight,
    required bool showGrid,
    required double scale,
    required bool isToolbarVisible,
  }) {
    return EditorSnapshot(
      nodes: graph.nodes.values.map(SerializableNode.fromNode).toList(),
      connections: graph.connections
          .map(SerializableConnection.fromConnection)
          .toList(),
      nodeWidth: nodeWidth,
      nodeHeight: nodeHeight,
      showGrid: showGrid,
      scale: scale,
      isToolbarVisible: isToolbarVisible,
    );
  }

  // EditorSnapshot (после jsonDecode) -> FlowchartGraph + настройки вида
  static RestoredState fromSnapshot(EditorSnapshot s) {
    final nodes = <String, NodeModel>{};
    for (final sn in s.nodes) {
      final n = sn.toNode();
      nodes[n.name] = n;
    }
    return RestoredState(
      graph: FlowchartGraph(
        nodes: nodes,
        connections: s.connections.map((c) => c.toConnection()).toList(),
      ),
      nodeSize: Size(s.nodeWidth, s.nodeHeight),
      showGrid: s.showGrid,
      scale: s.scale,
      isToolbarVisible: s.isToolbarVisible,
    );
  }
}

class RestoredState {
  final FlowchartGraph graph;
  final Size nodeSize;
  final bool showGrid;
  final double scale;
  final bool isToolbarVisible;
  RestoredState({
    required this.graph,
    required this.nodeSize,
    required this.showGrid,
    required this.scale,
    required this.isToolbarVisible,
  });
}
