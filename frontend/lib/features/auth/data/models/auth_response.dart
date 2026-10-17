import 'user.dart';
import 'auth_tokens.dart';
import '../../../../core/network/json_keys.dart';

class AuthResponse {
  final User user;
  final AuthTokens tokens;

  const AuthResponse({required this.user, required this.tokens});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    user: User.fromJson(json[JsonKeys.user] as Map<String, dynamic>),
    tokens: AuthTokens.fromJson(json),
  );

  Map<String, dynamic> toJson() => {
    JsonKeys.user: user.toJson(),
    ...tokens.toJson(),
  };
}
