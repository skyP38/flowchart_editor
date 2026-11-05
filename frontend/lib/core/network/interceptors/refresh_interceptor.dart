import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api_paths.dart';
import '../http_headers.dart';
import '../json_keys.dart';
import '../token_storage.dart';

// Ловит 401, пытается обновить access-токен через refresh-токен и повторить исходный запрос
// Если обновить не удалось - зовет onUnauthorized
// Ключевые моменты:
//  - защита от рекурсии: refresh-запрос помечается __skipInterceptors;
//  - защита от повторного повтора: __retried в extra;
//  - дедупликация: одновременные 401 ждут один общий future.
class RefreshInterceptor extends Interceptor {
  final Dio _dio;
  final TokenStorage _storage;
  final void Function()? onUnauthorized;
  final void Function()? onUserBlocked;

  Future<String?>? _refreshFuture;

  RefreshInterceptor({
    required Dio dio,
    required TokenStorage storage,
    this.onUnauthorized,
    this.onUserBlocked,
  }) : _dio = dio,
       _storage = storage;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.requestOptions.extra['__skipInterceptors'] == true) {
      return handler.next(err);
    }

    final response = err.response;
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;
    final status = response?.statusCode;

    String? code;
    String? message;
    final data = response?.data;
    if (data is Map) {
      final inner = data['error'];
      if (inner is Map) {
        code = inner['code']?.toString();
        message = inner['message']?.toString();
      }
      code ??= data['code']?.toString();
      message ??= data['message']?.toString();
    }

    debugPrint(
      '=== [Refresh] ${err.requestOptions.method} '
      '${err.requestOptions.path} status=$status '
      'code=$code message=$message ===',
    );

    final blocked =
        status == 403 &&
        (code == 'user_blocked' ||
            code == 'forbidden' ||
            message == 'user is blocked');
    if (blocked) {
      await _storage.clear();
      onUserBlocked?.call();
      return handler.next(err);
    }

    // Реакция на 401 в защищенных запросах 1 раз
    if (status != 401 ||
        ApiPaths.isPublic(err.requestOptions.path) ||
        alreadyRetried) {
      return handler.next(err);
    }

    final newAccess = await _refreshTokens();
    if (newAccess == null) {
      // Refresh не удался - токены невалидны
      await _storage.clear();
      onUnauthorized?.call();
      return handler.next(err);
    }

    // Повторяем исходный запрос с новым access-токеном
    final options = err.requestOptions;
    options.headers[ApiHeaders.authorization] = ApiHeaders.bearer(newAccess);
    options.extra['__retried'] = true;

    try {
      final response = await _dio.fetch(options);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  // Дедупликация параллельных refresh-запросов:
  // если уже идет один - ждем его результат
  Future<String?> _refreshTokens() {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final future = _doRefresh();
    _refreshFuture = future;
    future.whenComplete(() => _refreshFuture = null);
    return future;
  }

  // Сетевой вызов /api/auth/refresh
  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiPaths.refresh,
        data: {JsonKeys.refreshToken: refreshToken},
        options: Options(extra: {'__skipInterceptors': true}),
      );

      final data = res.data;
      if (data == null) return null;

      final access = data[JsonKeys.accessToken] as String?;
      final refresh = data[JsonKeys.refreshToken] as String?;
      if (access == null || refresh == null) return null;

      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } catch (e) {
      debugPrint('RefreshInterceptor: refresh failed: $e');
      return null;
    }
  }
}
