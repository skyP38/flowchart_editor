class Session {
  final int id;
  final String? deviceName;
  final String? userAgent;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const Session({
    required this.id,
    required this.createdAt,
    this.deviceName,
    this.userAgent,
    this.lastUsedAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: (json['id'] as num).toInt(),
    deviceName: json['deviceName'] as String?,
    userAgent: json['userAgent'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastUsedAt: json['lastUsedAt'] == null
        ? null
        : DateTime.parse(json['lastUsedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceName': deviceName,
    'userAgent': userAgent,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
  };
}
