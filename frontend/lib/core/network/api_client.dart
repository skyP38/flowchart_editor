import 'package:dio/dio.dart';
import 'api_error.dart';
import 'token_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/refresh_interceptor.dart';
import 'interceptors/error_interceptor.dart';

class ApiClient {
  final Dio _dio;
  // final TokenStorage _storage;

  ApiClient({
    required String baseUrl,
    required TokenStorage storage,
    void Function()? onUnauthorized,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 20),
    Duration sendTimeout = const Duration(seconds: 20),
  }) : // _storage = storage,
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: connectTimeout,
           receiveTimeout: receiveTimeout,
           sendTimeout: sendTimeout,
           headers: {
             'Content-Type': 'application/json',
             'Accept': 'application/json',
           },
           responseType: ResponseType.json,
           // validateStatus по умолчанию: 200..299 - успех, остальное - DioException
         ),
       ) {
    _dio.interceptors.addAll([
      ErrorInterceptor(),
      AuthInterceptor(storage),
      RefreshInterceptor(
        dio: _dio,
        storage: storage,
        onUnauthorized: onUnauthorized,
      ),

      // if (const bool.fromEnvironment('dart.vm.product') == false)
      //   LoggingInterceptor(),
    ]);
  }

  // Публичные типизированные методы
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request<T>(
    () => _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request<T>(
    () => _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request<T>(
    () => _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request<T>(
    () => _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _request<T>(
    () => _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  // оборачивает любой запрос и превращает ошибки в ApiError
  Future<T> _request<T>(Future<Response<T>> Function() send) async {
    try {
      final response = await send();
      return _unwrap<T>(response);
    } on DioException catch (e) {
      final err = e.error;
      if (err is ApiError) throw err;
      throw ApiError.fromDioException(e);
    } catch (e) {
      throw ApiError(
        type: ApiErrorType.unknown,
        message: 'Unknown error: $e',
        originalError: e,
      );
    }
  }

  T _unwrap<T>(Response<T> response) {
    if (T == Null || response.statusCode == 204) {
      //204 No Content
      return null as T;
    }

    final Object? data = response.data;
    if (data is T) return data;

    if (data is Map) {
      final dynamic m = Map<String, dynamic>.from(data);
      if (m is T) return m;
    }
    throw ApiError(
      type: ApiErrorType.unknown,
      message: 'Unexpected response format: ${data.runtimeType} → $T',
      statusCode: response.statusCode,
    );
  }

  Dio get raw => _dio;
}
