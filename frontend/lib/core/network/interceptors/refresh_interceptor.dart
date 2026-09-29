import 'package:dio/dio.dart';
import '../token_storage.dart';

class RefreshInterceptor extends Interceptor {
  final Dio _dio;
  final TokenStorage _storage;
  final void Function()? onUnauthorized;

  Future<String?>? _refreshFuture;

  static const _publicPaths = <String>[
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/password/request',
    '/auth/password/confirm',
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
    final response = err.response;
    final path = err.requestOptions.path;
    final isPublic = _publicPaths.any((p) => path.startsWith(p));
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;

    if (response?.statusCode != 401 || isPublic || alreadyRetried) {
      return handler.next(err);
    }

    final newAccess = await _refreshTokens();
    if (newAccess == null) {
      await _storage.clear();
      onUnauthorized?.call();
      return handler.next(err);
    }

    // Повторяем исходный запрос с новым access-токеном.
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

  // Возвращает новый access-токен или null при неудаче.
  Future<String?> _refreshTokens() {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final future = _doRefresh();
    _refreshFuture = future;
    future.whenComplete(() => _refreshFuture = null);
    return future;
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final bare = Dio(
        BaseOptions(
          baseUrl: _dio.options.baseUrl,
          connectTimeout: _dio.options.connectTimeout,
          receiveTimeout: _dio.options.receiveTimeout,
        ),
      );

      final res = await bare.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          extra: {'__skipInterceptors': true},
        ),
      );

      final data = res.data;
      if (data == null) return null;

      final access = data['accessToken'] as String?;
      final refresh = data['refreshToken'] as String?;
      if (access == null || refresh == null) return null;

      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } catch (_) {
      return null;
    }
  }
}
