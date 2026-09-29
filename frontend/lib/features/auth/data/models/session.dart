class Session {
  final int id;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final bool active;
  final bool current;

  const Session({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
    required this.active,
    required this.current,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: (json['id'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    revokedAt: json['revoked_at'] == null
        ? null
        : DateTime.parse(json['revoked_at'] as String),
    active: json['active'] as bool? ?? false,
    current: json['current'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'revoked_at': revokedAt?.toIso8601String(),
    'active': active,
    'current': current,
  };
}
