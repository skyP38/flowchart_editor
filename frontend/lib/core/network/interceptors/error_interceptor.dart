import 'package:dio/dio.dart';
import '../api_error.dart';

// Перехватчик, который превращает DioException в DioException с ApiError внутри `error`
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // отмененный запросы - не ошибка
    if (err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }

    final apiError = ApiError.fromDioException(err);
    final wrapped = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: apiError, // доменная ошибка
      stackTrace: err.stackTrace,
    );
    return handler.next(wrapped);
  }
}
