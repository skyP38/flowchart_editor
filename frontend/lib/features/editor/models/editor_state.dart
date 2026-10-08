import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'flow_models.dart';
import '../factories/node_factory.dart';
import 'editor_models.dart';

part 'editor_state.g.dart';

// Сериализуемое представление узла
@JsonSerializable()
class SerializableNode {
  final String id;
  final String name;
  final String dataType;
  final String text;
  final double posX;
  final double posY;

  SerializableNode({
    required this.id,
    required this.name,
    required this.dataType,
    required this.text,
    required this.posX,
    required this.posY,
  });

  // Снимок доменного узла для сохранения в JSON
  factory SerializableNode.fromNode(NodeModel node) {
    return SerializableNode(
      id: node.id,
      name: node.name,
      dataType: node.data.runtimeType.toString(),
      text: node.data.text,
      posX: node.position.dx,
      posY: node.position.dy,
    );
  }

  // Восстановление узла из JSON 
  NodeModel toNode() {
    GostNodeData data;
    switch (dataType) {
      case 'ProcessBlock': data = ProcessBlock(text); break;
      case 'LogicBlock': data = LogicBlock(text); break;
      case 'TerminalBlock': data = TerminalBlock(text); break;
      case 'IOBlock': data = IOBlock(text); break;
      case 'SubroutineBlock': data = SubroutineBlock(text); break;
      case 'ForBlock': data = ForBlock(text); break;
      default: data = ProcessBlock(text);
    }
    return NodeModel(
      id: id,
      name: name,
      data: data,
      position: Offset(posX, posY),
    );
  }

  Map<String, dynamic> toJson() => _$SerializableNodeToJson(this);
  factory SerializableNode.fromJson(Map<String, dynamic> json) => _$SerializableNodeFromJson(json);
}


// Сериализуемое представление связи
@JsonSerializable()
class SerializableConnection {
  final String? id;
  final String sourceNodeName;
  final String sourcePort;
  final String targetNodeName;
  final String targetPort;

  SerializableConnection({
    this.id,
    required this.sourceNodeName,
    required this.sourcePort,
    required this.targetNodeName,
    required this.targetPort,
  });

  factory SerializableConnection.fromConnection(ConnectionData conn) {
    return SerializableConnection(
      id: conn.id,
      sourceNodeName: conn.sourceNodeName,
      sourcePort: conn.sourcePort,
      targetNodeName: conn.targetNodeName,
      targetPort: conn.targetPort,
    );
  }

  ConnectionData toConnection() {
    return ConnectionData(
      id: id ?? 'unknown',
      sourceNodeName: sourceNodeName,
      sourcePort: sourcePort,
      targetNodeName: targetNodeName,
      targetPort: targetPort,
    );
  }

  Map<String, dynamic> toJson() => _$SerializableConnectionToJson(this);
  factory SerializableConnection.fromJson(Map<String, dynamic> json) => _$SerializableConnectionFromJson(json);
}

// Полный снимок состояния редактора: узлы, связи и настройки вида
@JsonSerializable()
class EditorSnapshot {
  final List<SerializableNode> nodes;
  final List<SerializableConnection> connections;
  final double nodeWidth;
  final double nodeHeight;
  final bool showGrid;
  final double scale;
  final bool isToolbarVisible;

  EditorSnapshot({
    required this.nodes,
    required this.connections,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.showGrid,
    required this.scale,
    required this.isToolbarVisible,
  });

  Map<String, dynamic> toJson() => _$EditorSnapshotToJson(this);
  factory EditorSnapshot.fromJson(Map<String, dynamic> json) => _$EditorSnapshotFromJson(json);
}
