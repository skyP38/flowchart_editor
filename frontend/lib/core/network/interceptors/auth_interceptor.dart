import 'package:dio/dio.dart';
import '../token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage _storage;

  // Пути, к которым access-токен не добавляется
  static const _publicPaths = <String>[
    '/api/auth/login',
    '/api/auth/register',
    '/api/auth/refresh',
  ];

  AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['__skipInterceptors'] == true) {
      return handler.next(options);
    }
    final isPublic = _publicPaths.any((p) => options.path.startsWith(p));
    if (isPublic) {
      return handler.next(options);
    }

    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }
}
