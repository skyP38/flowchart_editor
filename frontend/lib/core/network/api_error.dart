import 'package:dio/dio.dart';

enum ApiErrorType {
  network, // нет соединения
  timeout, // таймаут
  cancelled, // запрос отменён
  unauthorized, // 401
  forbidden, // 403
  notFound, // 404
  validation, // 400 / 422
  server, // 5xx
  unknown, // всё остальное
}

class ApiError implements Exception {
  final ApiErrorType type;
  final int? statusCode;
  final String? code; // от backend
  final String message; // выдающееся пользователю сообщение
  final Map<String, dynamic>? details; // ошибки валидации по полям
  final Object? originalError; // для логов

  const ApiError({
    required this.type,
    required this.message,
    this.statusCode,
    this.code,
    this.details,
    this.originalError,
  });

  bool get isUnauthorized => type == ApiErrorType.unauthorized;
  bool get isNetwork => type == ApiErrorType.network;
  bool get isTimeout => type == ApiErrorType.timeout;
  bool get isValidation => type == ApiErrorType.validation;
  bool get isServer => type == ApiErrorType.server;

  String? fieldError(String field) {
    final d = details;
    if (d == null) return null;
    final v = d[field];
    if (v is String) return v;
    if (v is List && v.isNotEmpty) return v.first.toString();
    return null;
  }

  // Конвертация из DioException
  factory ApiError.fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiError(
          type: ApiErrorType.timeout,
          message: 'The waiting time has been exceeded. Check the connection.',
          originalError: e,
        );

      case DioExceptionType.connectionError:
        return ApiError(
          type: ApiErrorType.network,
          message: 'There is no connection to the server.',
          originalError: e,
        );

      case DioExceptionType.cancel:
        return ApiError(
          type: ApiErrorType.cancelled,
          message: 'The request has been canceled.',
          originalError: e,
        );

      case DioExceptionType.badCertificate:
        return ApiError(
          type: ApiErrorType.network,
          message: 'There is a problem with the security certificate.',
          originalError: e,
        );

      case DioExceptionType.badResponse:
        final response = e.response;
        if (response == null) {
          return ApiError(
            type: ApiErrorType.unknown,
            message: 'An empty server response.',
            originalError: e,
          );
        }
        return ApiError.fromResponse(response, originalError: e);

      case DioExceptionType.transformTimeout:
        return ApiError(
          type: ApiErrorType.timeout,
          message:
              'The waiting time for processing the response has been exceeded.',
          originalError: e,
        );

      case DioExceptionType.unknown:
        return ApiError(
          type: ApiErrorType.unknown,
          message: 'Unknown error. Try again later.',
          originalError: e,
        );
    }
  }

  // Конвертация из Response
  factory ApiError.fromResponse(Response response, {Object? originalError}) {
    final status = response.statusCode ?? 0;
    final data = response.data;

    String? code;
    String? message;
    Map<String, dynamic>? details;

    if (data is Map<String, dynamic>) {
      code = data['code']?.toString();
      message = data['message']?.toString() ?? data['error']?.toString();
      final rawDetails = data['details'];
      if (rawDetails is Map) {
        details = rawDetails.map((k, v) => MapEntry(k.toString(), v));
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    }

    final type = _typeFromStatus(status);
    return ApiError(
      type: type,
      statusCode: status,
      code: code,
      details: details,
      message: message ?? _defaultMessageFor(type),
      originalError: originalError,
    );
  }

  static ApiErrorType _typeFromStatus(int status) {
    if (status == 401) return ApiErrorType.unauthorized;
    if (status == 403) return ApiErrorType.forbidden;
    if (status == 404) return ApiErrorType.notFound;
    if (status == 400 || status == 422) return ApiErrorType.validation;
    if (status >= 500) return ApiErrorType.server;
    return ApiErrorType.unknown;
  }

  static String _defaultMessageFor(ApiErrorType type) {
    switch (type) {
      case ApiErrorType.unauthorized:
        return 'Authorization is required.';
      case ApiErrorType.forbidden:
        return 'There is no access.';
      case ApiErrorType.notFound:
        return 'Not found.';
      case ApiErrorType.validation:
        return 'Check the entered data.';
      case ApiErrorType.server:
        return 'Server error. Try again later.';
      case ApiErrorType.network:
        return 'There is no connection to the server.';
      case ApiErrorType.timeout:
        return 'The waiting time has been exceeded.';
      case ApiErrorType.cancelled:
        return 'The request has been canceled.';
      case ApiErrorType.unknown:
        return 'Unknown error.';
    }
  }

  @override
  String toString() =>
      'ApiError(type: $type, status: $statusCode, code: $code, message: $message)';
}
