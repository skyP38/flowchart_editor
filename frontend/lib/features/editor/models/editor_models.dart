import 'package:flowchart_editor_frontend/features/editor/models/flow_models.dart';
import 'package:flutter/material.dart';
import '../factories/node_factory.dart';

// Обертка над NodeModel с актуальной позицией на канвасе
class NodeWidgetData {
  NodeModel node;

  NodeWidgetData({required this.node});

  Offset get position => node.position;
  set position(Offset value) {
    node = node.copyWith(position: value);
  }

  GostNodeData get data => node.data;
  set data(GostNodeData value) {
    node = node.copyWith(data: value);
  }
}

// Описание связи между двумя блоками
//
// sourcePort/targetPort - имена портов:
//   - out - единственный выход обычного блока;
//   - yes/no - выходы LogicBlock;
//   - body - тело цикла;
//   - exit - выход из цикла;
//   - loopback - обратная связь заглушки тела цикла к самому For;
//   - in - вход любого блока.
class ConnectionData {
  final String? id;
  final String sourceNodeName;
  final String sourcePort;
  final String targetNodeName;
  final String targetPort;
  ConnectionData({
    this.id,
    required this.sourceNodeName,
    required this.sourcePort,
    required this.targetNodeName,
    required this.targetPort,
  });
}

// Точка "+" на канвасе, по нажатию на которую в разрыв связи
// вставляется новый блок выбранного прототипа
class InsertionPoint {
  // Координата центра кружка на канвасе
  final Offset position;
  // Связь, в разрыв которой будет вставлен блок
  final ConnectionData connection;
  // Флаг для логического блока - для создания доп плюса
  final bool isAfterMerge;
  // Для логического блока возможно перенаправление
  final String? mergeOtherConnId;
  InsertionPoint(
    this.position,
    this.connection, {
    this.isAfterMerge = false,
    this.mergeOtherConnId,
  });
}
