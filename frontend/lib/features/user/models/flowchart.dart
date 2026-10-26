import 'package:flutter/foundation.dart';

class Flowchart {
  final int id;
  final String name;
  final DateTime modified;
  final String? previewSvg;

  const Flowchart({
    required this.id,
    required this.name,
    required this.modified,
    this.previewSvg,
  });

  factory Flowchart.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final rawSvg = rawData is Map ? rawData['previewSvg'] : null;

    final previewSvg = rawSvg is String ? rawSvg : null;

    debugPrint(
      'Flowchart ${json['id']}: previewSvg length = '
      '${previewSvg?.length ?? 0}',
    );
    return Flowchart(
      id: json['id'] as int,
      name: json['name'] as String,
      modified: DateTime.parse(
        (json['dateUpdate'] ?? json['dateCreate']) as String,
      ),
      previewSvg: previewSvg,
    );
  }
}
