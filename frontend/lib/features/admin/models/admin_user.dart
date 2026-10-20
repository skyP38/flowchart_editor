class AdminUser {
  final int id;
  final String login;
  final String name;
  final String role;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final bool isActive;

  const AdminUser({
    required this.id,
    required this.login,
    required this.name,
    required this.role,
    required this.createdAt,
    required this.isActive,
    this.lastLogin,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: (json['id'] as num).toInt(),
    login: json['login'] as String? ?? '',
    name: json['uname'] as String? ?? '',
    role: json['role'] as String? ?? 'user',
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    lastLogin: json['lastLogin'] == null
        ? null
        : DateTime.parse(json['lastLogin'] as String).toLocal(),
    isActive: json['isActive'] as bool? ?? false,
  );
}
