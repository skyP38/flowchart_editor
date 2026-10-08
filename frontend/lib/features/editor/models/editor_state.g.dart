// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editor_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SerializableNode _$SerializableNodeFromJson(Map<String, dynamic> json) =>
    SerializableNode(
      id: json['id'] as String,
      name: json['name'] as String,
      dataType: json['dataType'] as String,
      text: json['text'] as String,
      posX: (json['posX'] as num).toDouble(),
      posY: (json['posY'] as num).toDouble(),
    );

Map<String, dynamic> _$SerializableNodeToJson(SerializableNode instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'dataType': instance.dataType,
      'text': instance.text,
      'posX': instance.posX,
      'posY': instance.posY,
    };

SerializableConnection _$SerializableConnectionFromJson(
  Map<String, dynamic> json,
) => SerializableConnection(
  id: json['id'] as String?,
  sourceNodeName: json['sourceNodeName'] as String,
  sourcePort: json['sourcePort'] as String,
  targetNodeName: json['targetNodeName'] as String,
  targetPort: json['targetPort'] as String,
);

Map<String, dynamic> _$SerializableConnectionToJson(
  SerializableConnection instance,
) => <String, dynamic>{
  'id': instance.id,
  'sourceNodeName': instance.sourceNodeName,
  'sourcePort': instance.sourcePort,
  'targetNodeName': instance.targetNodeName,
  'targetPort': instance.targetPort,
};

EditorSnapshot _$EditorSnapshotFromJson(Map<String, dynamic> json) =>
    EditorSnapshot(
      nodes: (json['nodes'] as List<dynamic>)
          .map((e) => SerializableNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      connections: (json['connections'] as List<dynamic>)
          .map(
            (e) => SerializableConnection.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      nodeWidth: (json['nodeWidth'] as num).toDouble(),
      nodeHeight: (json['nodeHeight'] as num).toDouble(),
      showGrid: json['showGrid'] as bool,
      scale: (json['scale'] as num).toDouble(),
      isToolbarVisible: json['isToolbarVisible'] as bool,
    );

Map<String, dynamic> _$EditorSnapshotToJson(EditorSnapshot instance) =>
    <String, dynamic>{
      'nodes': instance.nodes,
      'connections': instance.connections,
      'nodeWidth': instance.nodeWidth,
      'nodeHeight': instance.nodeHeight,
      'showGrid': instance.showGrid,
      'scale': instance.scale,
      'isToolbarVisible': instance.isToolbarVisible,
    };
