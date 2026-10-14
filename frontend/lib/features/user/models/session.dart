class Session {
  final int id;
  final int userId;
  final String tokenHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  const Session({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as int,
      userId: json['userId'] as int,
      tokenHash: json['tokenHash'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      revokedAt: json['revokedAt'] != null
          ? DateTime.parse(json['revokedAt'] as String)
          : null,
    );
  }

  /// Активна, если не отозвана и не истекла.
  bool get isActive =>
      revokedAt == null && expiresAt.isAfter(DateTime.now());

  String get statusLabel =>
      isActive ? 'The current session' : 'Inactive session';

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
/*class Session {
  final int id;
  final int userId;
  final DateTime dateCreate;
  final bool isActive;
  final DateTime? closingDate;

  const Session({
    required this.id,
    required this.userId,
    required this.dateCreate,
    required this.isActive,
    this.closingDate,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as int,
      userId: json['userId'] as int,
      dateCreate: DateTime.parse(json['dateCreate'] as String),
      isActive: json['isActive'] as bool,
      closingDate: json['closingDate'] != null
          ? DateTime.parse(json['closingDate'] as String)
          : null,
    );
  }

  // Что показывать в колонке STATUS
  String get statusLabel =>
      isActive ? 'The current session' : 'Inactive session';

  // Что показывать в колонке ACTIVITY
  String get activityLabel {
    if (isActive) return 'Active now';
    final d = closingDate ?? dateCreate;
    return _formatDateTime(d);
  }

  // Что показывать в колонке CREATED (вместо GEOLOCATION)
  String get createdLabel => _formatDateTime(dateCreate);

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)} '
        '${two(d.day)}.${two(d.month)}.${d.year.toString().substring(2)}';
  }
}*/
