import 'package:dio/dio.dart';

import '../api_paths.dart';
import '../http_headers.dart';
import '../token_storage.dart';

// Подставляет Authorization: Bearer <access> во все защищенные запросы
class AuthInterceptor extends Interceptor {
  final TokenStorage _storage;

  AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // защита от рекурсии - тег в RefreshInterceptor
    if (options.extra['__skipInterceptors'] == true) {
      return handler.next(options);
    }
    if (ApiPaths.isPublic(options.path)) {
      return handler.next(options);
    }

    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers[ApiHeaders.authorization] = ApiHeaders.bearer(token);
    }
    return handler.next(options);
  }
}
