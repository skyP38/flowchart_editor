import 'package:dio/dio.dart';

import '../token_storage.dart';

// Ловит 401, пытается обновить access-токен через refresh-токен и повторить исходный запрос
// Если обновить не удалось - зовет onUnauthorized
// Ключевые моменты:
//  - защита от рекурсии: refresh-запрос помечается `__skipInterceptors`;
//  - защита от повторного повтора: `__retried` в extra;
//  - дедупликация: одновременные 401 ждут один общий future.
class RefreshInterceptor extends Interceptor {
  final Dio _dio;
  final TokenStorage _storage;
  final void Function()? onUnauthorized;

  Future<String?>? _refreshFuture;

  static const _publicPaths = <String>[
    '/api/auth/login',
    '/api/auth/register',
    '/api/auth/refresh',
  ];

  RefreshInterceptor({
    required Dio dio,
    required TokenStorage storage,
    this.onUnauthorized,
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
    final path = err.requestOptions.path;
    final isPublic = _publicPaths.any((p) => path.startsWith(p));
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;

    // Реакция на 401 в защищенных запросах 1 раз
    if (response?.statusCode != 401 || isPublic || alreadyRetried) {
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
    options.headers['Authorization'] = 'Bearer $newAccess';
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
        '/api/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'__skipInterceptors': true}),
      );

      final data = res.data;
      if (data == null) return null;

      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      if (access == null || refresh == null) return null;

      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } catch (_) {
      return null;
    }
  }
}
