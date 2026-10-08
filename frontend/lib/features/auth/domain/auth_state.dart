import '../../../core/network/api_error.dart';
import '../data/models/user.dart';

// Состояние авторизации
sealed class AuthState {
  const AuthState();
}

// до вызова AuthRepository.init()
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

// Идет асинхронная операция
final class AuthLoading extends AuthState {
  final User? user;

  const AuthLoading({this.user});

  bool get isBackground => user != null;
}

// Пользователь не авторизован
final class AuthUnauthenticated extends AuthState {
  final String? message;
  final ApiError? error;

  const AuthUnauthenticated({this.message, this.error});
}

// Пользователь авторизован
final class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated(this.user);
}

// Техническая ошибка: не удалось восстановить сессию при старте
final class AuthError extends AuthState {
  final ApiError error;

  const AuthError(this.error);
}
