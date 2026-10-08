import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/token_storage.dart';
import '../data/api/auth_api.dart';
import 'auth_state.dart';

// Единая точка входа для всей логики авторизации
class AuthRepository extends ChangeNotifier {
  final AuthApi _api;
  final TokenStorage _storage;

  AuthState _state = const AuthUnknown();
  AuthState get state => _state;

  bool _disposed = false;

  // Защита от параллельных вызовов
  Future<void>? _initFuture;

  AuthRepository({required AuthApi api, required TokenStorage storage})
    : _api = api,
      _storage = storage;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  // Публичный API

  /// Восстановление сессии при старте приложения
  Future<void> init() {
    final existing = _initFuture;
    if (existing != null) return existing;

    final future = _doInit();
    _initFuture = future;
    unawaited(future.whenComplete(() => _initFuture = null));
    return future;
  }

  Future<void> login({required String login, required String password}) async {
    if (_state is AuthLoading) return;

    try {
      final response = await _api.login(login: login, password: password);
      await _storage.saveTokens(
        accessToken: response.tokens.accessToken,
        refreshToken: response.tokens.refreshToken,
      );
      _setState(AuthAuthenticated(response.user));
    } on ApiError catch (e) {
      _handleAuthOperationError(e);
    } catch (e) {
      _setState(AuthError(_wrapUnknown(e)));
    }
  }

  Future<void> register({
    required String login,
    required String uname,
    required String password,
  }) async {
    if (_state is AuthLoading) return;

    try {
      final response = await _api.register(
        login: login,
        uname: uname,
        password: password,
      );
      await _storage.saveTokens(
        accessToken: response.tokens.accessToken,
        refreshToken: response.tokens.refreshToken,
      );
      _setState(AuthAuthenticated(response.user));
    } on ApiError catch (e) {
      _handleAuthOperationError(e);
    } catch (e) {
      _setState(AuthError(_wrapUnknown(e)));
    }
  }

  // Локальный выход
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();

    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {}
    }

    await _storage.clear();
    _setState(const AuthUnauthenticated());
  }

  void onSessionExpired() {
    debugPrint('AuthRepository: onSessionExpired() called');
    unawaited(_storage.clear());
    _setState(const AuthUnauthenticated(message: 'Session expired'));
  }

  // Внутренняя логика
  Future<void> _doInit() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      _setState(const AuthUnauthenticated());
      return;
    }

    try {
      final response = await _api.refresh(refreshToken);
      await _storage.saveTokens(
        accessToken: response.tokens.accessToken,
        refreshToken: response.tokens.refreshToken,
      );

      final user = await _api.me();
      _setState(AuthAuthenticated(user));
    } catch (_) {
      await _storage.clear();
      _setState(const AuthUnauthenticated());
    }
  }

  void _handleAuthOperationError(ApiError error) {
    _setState(AuthUnauthenticated(message: error.message, error: error));
  }

  ApiError _wrapUnknown(Object e) => ApiError(
    type: ApiErrorType.unknown,
    message: 'Unknown error: $e',
    originalError: e,
  );

  // Обновляет состояние и уведомляет слушателей
  void _setState(AuthState next) {
    if (_disposed) return;
    debugPrint('AuthRepository: ${_state.runtimeType} -> ${next.runtimeType}');
    _state = next;
    notifyListeners();
  }
}
