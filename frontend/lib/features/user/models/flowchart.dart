class Flowchart {
  final int id;
  final String name;
  final DateTime modified;

  const Flowchart({
    required this.id,
    required this.name,
    required this.modified,
  });

  factory Flowchart.fromJson(Map<String, dynamic> json) {
    return Flowchart(
      id: json['id'] as int,
      name: json['name'] as String,
      modified: DateTime.parse(
        (json['dateUpdate'] ?? json['dateCreate']) as String,
      ),
    );
  }
}
