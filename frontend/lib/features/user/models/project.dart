import 'flowchart.dart';

class Project {
  final int id;
  final String name;
  final DateTime modified;
  final List<Flowchart> flowcharts;

  const Project({
    required this.id,
    required this.name,
    required this.modified,
    this.flowcharts = const [],
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    final rawCharts = (json['flowcharts'] as List<dynamic>?) ?? [];
    return Project(
      id: json['id'] as int,
      name: json['name'] as String,
      modified: DateTime.parse(
        (json['dateUpdate'] ?? json['dateCreate']) as String,
      ),
      flowcharts: rawCharts
          .map((j) => Flowchart.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }
}
