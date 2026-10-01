import 'user.dart';
import 'auth_tokens.dart';

class AuthResponse {
  final User user;
  final AuthTokens tokens;

  const AuthResponse({required this.user, required this.tokens});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    user: User.fromJson(json['user'] as Map<String, dynamic>),
    tokens: AuthTokens.fromJson(json),
  );

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'tokens': tokens.toJson(),
  };
}
