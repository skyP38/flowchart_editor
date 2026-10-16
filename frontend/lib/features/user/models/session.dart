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

  bool get isActive => active;

  String get statusLabel => current
      ? 'The current session'
      : (isActive ? 'Active session' : 'Inactive session');

  String get activityLabel {
    if (isActive) return 'Active now';
    final d = revokedAt ?? createdAt;
    return _formatDateTime(d);
  }

  String get createdLabel => _formatDateTime(createdAt);

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)} '
        '${two(d.day)}.${two(d.month)}.${d.year.toString().substring(2)}';
  }
}
//   /// Активна, если не отозвана и не истекла.
//   bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());

//   String get statusLabel =>
//       isActive ? 'The current session' : 'Inactive session';

//   String get activityLabel {
//     if (isActive) return 'Active now';
//     final d = revokedAt ?? createdAt;
//     return _formatDateTime(d);
//   }

//   String get createdLabel => _formatDateTime(createdAt);

//   String _formatDateTime(DateTime d) {
//     String two(int n) => n.toString().padLeft(2, '0');
//     return '${two(d.hour)}:${two(d.minute)} '
//         '${two(d.day)}.${two(d.month)}.${d.year.toString().substring(2)}';
//   }
// }
