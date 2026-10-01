class User {
  final String id;
  final String? name;
  final String? login;
  final String? role;

  const User({required this.id, this.name, this.login, this.role});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    name: (json['uname'] ?? json['name']) as String?,
    login: json['login'] as String?,
    role: json['role'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uname': name,
    'login': login,
    'role': role,
  };
}
