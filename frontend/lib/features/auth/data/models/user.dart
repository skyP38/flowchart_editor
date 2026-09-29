class User {
  final String id;
  final String email;
  final String? name;
  final String? login;

  const User({required this.id, required this.email, this.name, this.login});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    email: json['email'] as String,
    name: json['name'] as String?,
    login: json['login'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'login': login,
  };
}
