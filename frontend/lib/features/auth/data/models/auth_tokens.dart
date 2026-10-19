import '../../../../core/network/json_keys.dart';

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json[JsonKeys.accessToken] as String,
    refreshToken: json[JsonKeys.refreshToken] as String,
    expiresIn: (json[JsonKeys.expiresIn] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    JsonKeys.accessToken: accessToken,
    JsonKeys.refreshToken: refreshToken,
    JsonKeys.expiresIn: expiresIn,
  };
}
