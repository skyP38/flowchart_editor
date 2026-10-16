import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import '../factories/node_factory.dart';
import '../models/editor_models.dart';
import '../models/flow_models.dart';
import 'flowchart_graph.dart';

class InsertionResult {
  final FlowchartGraph graph;
  final String newRootName; // имя вставленного блока
  const InsertionResult(this.graph, this.newRootName);
}

class InsertionService {
  final Uuid _uuid;
  InsertionService([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  InsertionResult insertOnConnection(
    FlowchartGraph g,
    String connectionId,
    GostNodeData prototype,
  ) {
    final conn = g.connections.firstWhere((c) => c.id == connectionId);
    final newNode = NodeFactory.createNode(
      id: _uuid.v4(),
      data: prototype,
      position: Offset.zero,
    );

    var next = g.withNode(newNode).withoutConnection(connectionId);

    // source -> new
    next = next.withConnection(
      ConnectionData(
        id: _uuid.v4(),
        sourceNodeName: conn.sourceNodeName,
        sourcePort: conn.sourcePort,
        targetNodeName: newNode.name,
        targetPort: 'in',
      ),
    );

    if (prototype is LogicBlock) {
      next = next
          .withConnection(
            ConnectionData(
              id: _uuid.v4(),
              sourceNodeName: newNode.name,
              sourcePort: 'yes',
              targetNodeName: conn.targetNodeName,
              targetPort: conn.targetPort,
            ),
          )
          .withConnection(
            ConnectionData(
              id: _uuid.v4(),
              sourceNodeName: newNode.name,
              sourcePort: 'no',
              targetNodeName: conn.targetNodeName,
              targetPort: conn.targetPort,
            ),
          );
    } else if (prototype is ForBlock) {
      final body = NodeFactory.createNode(
        id: _uuid.v4(),
        data: const ProcessBlock('Тело цикла'),
        position: Offset.zero,
      );
      next = next
          .withNode(body)
          .withConnection(
            ConnectionData(
              id: _uuid.v4(),
              sourceNodeName: newNode.name,
              sourcePort: 'exit',
              targetNodeName: conn.targetNodeName,
              targetPort: conn.targetPort,
            ),
          )
          .withConnection(
            ConnectionData(
              id: _uuid.v4(),
              sourceNodeName: newNode.name,
              sourcePort: 'body',
              targetNodeName: body.name,
              targetPort: 'in',
            ),
          )
          .withConnection(
            ConnectionData(
              id: _uuid.v4(),
              sourceNodeName: body.name,
              sourcePort: 'out',
              targetNodeName: newNode.name,
              targetPort: 'loopback',
            ),
          );
    } else {
      next = next.withConnection(
        ConnectionData(
          id: _uuid.v4(),
          sourceNodeName: newNode.name,
          sourcePort: 'out',
          targetNodeName: conn.targetNodeName,
          targetPort: conn.targetPort,
        ),
      );
    }

    return InsertionResult(next, newNode.name);
  }
}
