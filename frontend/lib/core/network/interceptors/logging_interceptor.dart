import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../http_headers.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final auth = options.headers[ApiHeaders.authorization];
    debugPrint(
      '-> ${options.method} ${options.uri}'
      '${auth != null ? '  [$auth]' : ''}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('<- ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('- ${err.response?.statusCode} ${err.requestOptions.uri}');
    handler.next(err);
  }
}
