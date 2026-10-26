class AdminSession {
  final int id;
  final int userId;
  final String login;
  final String name;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final bool active;
  final String deviceName;
  final String location;

  const AdminSession({
    required this.id,
    required this.userId,
    required this.login,
    required this.name,
    required this.createdAt,
    required this.expiresAt,
    required this.active,
    this.revokedAt,
    this.deviceName = 'Unknown device',
    this.location = 'Not recorded',
  });

  factory AdminSession.fromJson(Map<String, dynamic> json) => AdminSession(
    id: (json['id'] as num).toInt(),
    userId: (json['userId'] as num).toInt(),
    login: json['login'] as String? ?? '',
    name: json['uname'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
    revokedAt: json['revokedAt'] == null
        ? null
        : DateTime.parse(json['revokedAt'] as String).toLocal(),
    active: json['active'] as bool? ?? false,
    deviceName: json['deviceName'] as String? ?? 'Unknown device',
    location: json['location'] as String? ?? 'Not recorded',
  );

  String get statusLabel => active ? 'Active session' : 'Inactive session';

  String get createdLabel => _formatDateTime(createdAt);

  String _formatDateTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)} '
        '${two(date.day)}.${two(date.month)}.${date.year.toString().substring(2)}';
  }
}
