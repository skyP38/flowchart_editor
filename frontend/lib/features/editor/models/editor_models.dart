import 'package:flutter/material.dart';
import '../factories/node_factory.dart';

// Обертка над NodeModel с актуальной позицией на канвасе
class NodeWidgetData {
  NodeModel node;
  Offset position;
  NodeWidgetData({required this.node, required this.position});
}

// Описание связи между двумя блоками.
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
  InsertionPoint(this.position, this.connection);
}
