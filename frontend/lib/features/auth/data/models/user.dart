class User {
  final String id;
  final String? name;
  final String? login;

  const User({required this.id, this.name, this.login});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    name: json['name'] as String?,
    login: json['login'] as String?,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'login': login};
}
