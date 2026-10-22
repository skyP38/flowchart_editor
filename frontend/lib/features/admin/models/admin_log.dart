class AdminLog {
  final int id;
  final int? userId;
  final String login;
  final String action;
  final DateTime createdAt;
  final String entity;
  final int? entityId;
  final String status;
  final String details;

  const AdminLog({
    required this.id,
    required this.login,
    required this.action,
    required this.createdAt,
    required this.entity,
    required this.status,
    required this.details,
    this.userId,
    this.entityId,
  });

  factory AdminLog.fromJson(Map<String, dynamic> json) {
    return AdminLog(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num?)?.toInt(),
      login: json['login'] as String? ?? 'system',
      action: json['action'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      entity: json['entity'] as String? ?? '',
      entityId: (json['entityId'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'Success',
      details: json['details'] as String? ?? '',
    );
  }

  String get objectLabel {
    if (entity.isEmpty) return '—';
    if (entityId == null) return entity;
    return '$entity:$entityId';
  }
}

class AdminLogPage {
  final List<AdminLog> logs;
  final int total;
  final int limit;
  final int offset;

  const AdminLogPage({
    required this.logs,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory AdminLogPage.fromJson(Map<String, dynamic> json) {
    final entries = json['logs'] as List<dynamic>? ?? const [];

    return AdminLogPage(
      logs: entries
          .map((entry) => AdminLog.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 10,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}
