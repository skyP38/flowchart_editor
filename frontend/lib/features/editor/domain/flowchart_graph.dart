import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';

// Иммутабельный снапшот блок-схемы
class FlowchartGraph {
  final Map<String, NodeModel> nodes;
  final List<ConnectionData> connections;

  // Индексы строятся один раз в конструкторе - все запросы O(1)
  final Map<String, List<ConnectionData>> outgoing;
  final Map<String, List<ConnectionData>> incoming;

  FlowchartGraph._(this.nodes, this.connections)
    : outgoing = _index(connections, bySource: true),
      incoming = _index(connections, bySource: false);

  factory FlowchartGraph({
    required Map<String, NodeModel> nodes,
    required List<ConnectionData> connections,
  }) =>
      FlowchartGraph._(Map.unmodifiable(nodes), List.unmodifiable(connections));

  factory FlowchartGraph.empty() =>
      FlowchartGraph(nodes: const {}, connections: const []);

  static Map<String, List<ConnectionData>> _index(
    List<ConnectionData> cs, {
    required bool bySource,
  }) {
    final m = <String, List<ConnectionData>>{};
    for (final c in cs) {
      final key = bySource ? c.sourceNodeName : c.targetNodeName;
      m.putIfAbsent(key, () => []).add(c);
    }
    return m;
  }

  // модификаторы
  FlowchartGraph withNode(NodeModel n) =>
      FlowchartGraph(nodes: {...nodes, n.name: n}, connections: connections);

  FlowchartGraph withoutNode(String name) => FlowchartGraph(
    nodes: {...nodes}..remove(name),
    connections: connections
        .where((c) => c.sourceNodeName != name && c.targetNodeName != name)
        .toList(),
  );

  FlowchartGraph withConnection(ConnectionData c) =>
      FlowchartGraph(nodes: nodes, connections: [...connections, c]);

  FlowchartGraph withoutConnection(String? id) => FlowchartGraph(
    nodes: nodes,
    connections: connections.where((c) => c.id != id).toList(),
  );

  FlowchartGraph replaceConnections(List<ConnectionData> cs) =>
      FlowchartGraph(nodes: nodes, connections: cs);

  // запросы
  NodeModel? findStart() {
    for (final n in nodes.values) {
      if (n.data is TerminalBlock && n.data.text == 'Start') return n;
    }
    return null;
  }

  bool isEnd(String name) {
    final d = nodes[name]?.data;
    return d is TerminalBlock && d.text == 'End';
  }

  bool isFor(String name) => nodes[name]?.data is ForBlock;
}
