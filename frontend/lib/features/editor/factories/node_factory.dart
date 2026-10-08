import 'package:flutter/material.dart';
import '../models/flow_models.dart';

// Узел блок-схемы
class NodeModel {
  final String id;
  final String name;
  GostNodeData data;
  Offset position;

  NodeModel({
    required this.id,
    required this.name,
    required this.data,
    required this.position,
  });
}

// Фабрика узлов
// name формируется из типа блока и первых 8 символов UUID
class NodeFactory {
  static NodeModel createNode({
    required String id,
    required GostNodeData data,
    required Offset position,
  }) {
    return NodeModel(
      id: id,
      name: '${data.runtimeType}_${id.substring(0, 8)}',
      data: data,
      position: position,
    );
  }
}
