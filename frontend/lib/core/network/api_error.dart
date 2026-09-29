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
          message: 'Превышено время ожидания. Проверьте соединение.',
          originalError: e,
        );

      case DioExceptionType.connectionError:
        return ApiError(
          type: ApiErrorType.network,
          message: 'Нет соединения с сервером.',
          originalError: e,
        );

      case DioExceptionType.cancel:
        return ApiError(
          type: ApiErrorType.cancelled,
          message: 'Запрос отменён.',
          originalError: e,
        );

      case DioExceptionType.badCertificate:
        return ApiError(
          type: ApiErrorType.network,
          message: 'Проблема с сертификатом безопасности.',
          originalError: e,
        );

      case DioExceptionType.badResponse:
        final response = e.response;
        if (response == null) {
          return ApiError(
            type: ApiErrorType.unknown,
            message: 'Пустой ответ сервера.',
            originalError: e,
          );
        }
        return ApiError.fromResponse(response, originalError: e);

      case DioExceptionType.transformTimeout:
        return ApiError(
          type: ApiErrorType.timeout,
          message: 'Превышено время ожидания обработки ответа.',
          originalError: e,
        );

      case DioExceptionType.unknown:
        return ApiError(
          type: ApiErrorType.unknown,
          message: 'Неизвестная ошибка. Попробуйте позже.',
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
        return 'Требуется авторизация.';
      case ApiErrorType.forbidden:
        return 'Нет доступа.';
      case ApiErrorType.notFound:
        return 'Не найдено.';
      case ApiErrorType.validation:
        return 'Проверьте введённые данные.';
      case ApiErrorType.server:
        return 'Ошибка сервера. Попробуйте позже.';
      case ApiErrorType.network:
        return 'Нет соединения с сервером.';
      case ApiErrorType.timeout:
        return 'Превышено время ожидания.';
      case ApiErrorType.cancelled:
        return 'Запрос отменён.';
      case ApiErrorType.unknown:
        return 'Неизвестная ошибка.';
    }
  }

  @override
  String toString() =>
      'ApiError(type: $type, status: $statusCode, code: $code, message: $message)';
}
