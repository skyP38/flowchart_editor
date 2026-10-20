import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowchart_editor_frontend/core/network/api_error.dart';

Response _resp(int status, dynamic data) => Response(
  requestOptions: RequestOptions(path: '/test'),
  statusCode: status,
  data: data,
);

DioException _dioErr(DioExceptionType type, {Response? response}) =>
    DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: type,
      response: response,
    );

void main() {
  group('ApiError.fromResponse', () {
    test('Parse format { error: { code, message } }', () {
      final err = ApiError.fromResponse(
        _resp(401, {
          'error': {'code': 'AUTH_INVALID_TOKEN', 'message': 'Invalid token'},
        }),
      );

      expect(err.statusCode, 401);
      expect(err.type, ApiErrorType.unauthorized);
      expect(err.code, 'AUTH_INVALID_TOKEN');
      expect(err.message, 'Invalid token');
    });

    test('Parse details in error', () {
      final err = ApiError.fromResponse(
        _resp(422, {
          'error': {
            'code': 'VALIDATION',
            'message': 'Bad input',
            'details': {'login': 'Invalid login'},
          },
        }),
      );

      expect(err.type, ApiErrorType.validation);
      expect(err.code, 'VALIDATION');
      expect(err.fieldError('login'), 'Invalid login');
    });

    test('parse format: { code, message }', () {
      final err = ApiError.fromResponse(
        _resp(400, {'code': 'SOME_CODE', 'message': 'Some message'}),
      );

      expect(err.code, 'SOME_CODE');
      expect(err.message, 'Some message');
    });

    test('String as message', () {
      final err = ApiError.fromResponse(_resp(500, 'pupupu'));

      expect(err.type, ApiErrorType.server);
      expect(err.message, 'pupupu');
    });

    test('Empty response', () {
      final err = ApiError.fromResponse(_resp(403, null));

      expect(err.type, ApiErrorType.forbidden);
      expect(err.message, 'There is no access.');
    });
  });

  group('ApiError.fromDioException', () {
    test('timeout', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final e = ApiError.fromDioException(_dioErr(t));
        expect(e.type, ApiErrorType.timeout, reason: '$t');
        // expect(e.isTimeout, isTrue);
      }
    });

    test('connectionError -> network', () {
      final e = ApiError.fromDioException(
        _dioErr(DioExceptionType.connectionError),
      );
      expect(e.type, ApiErrorType.network);
      // expect(e.isNetwork, isTrue);
    });

    test('badResponse', () {
      final e = ApiError.fromDioException(
        _dioErr(
          DioExceptionType.badResponse,
          response: _resp(401, {
            'error': {'code': 'AUTH', 'message': 'no'},
          }),
        ),
      );
      expect(e.type, ApiErrorType.unauthorized);
      expect(e.code, 'AUTH');
    });
  });

  group('ApiError: status -> type', () {
    final cases = <int, ApiErrorType>{
      0: ApiErrorType.unknown,
      400: ApiErrorType.validation,
      401: ApiErrorType.unauthorized,
      403: ApiErrorType.forbidden,
      404: ApiErrorType.notFound,
      422: ApiErrorType.validation,
      500: ApiErrorType.server,
      599: ApiErrorType.server,
    };
    cases.forEach((status, expected) {
      test('status $status -> $expected', () {
        final e = ApiError.fromResponse(_resp(status, null));
        expect(e.type, expected);
        expect(e.statusCode, status);
      });
    });
  });
}
