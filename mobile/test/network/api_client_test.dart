import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/network/api_exceptions.dart';
import 'package:wealthtrack/core/ui/copy_fallback.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import '../helpers/mocks.dart';

void main() {
  group('ApiClient', () {
    late ApiClient client;

    setUp(() {
      client = ApiClient(storage: MockSecureStorage());
    });

    group('handleError', () {
      test('returns ApiException as-is', () {
        final exc = ApiException('Test error', statusCode: 400);
        final result = client.handleError(exc);
        expect(result, same(exc));
      });

      test('returns UnauthorizedException for 401 without credential detail', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 401,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<UnauthorizedException>());
      });

      test('wrong login credentials stay credential error, not session expired', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            statusCode: 401,
            data: {'detail': 'Username atau password salah'},
            requestOptions: RequestOptions(path: '/auth/login'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect(result, isNot(isA<UnauthorizedException>()));
        expect(
          (result as ApiException).message,
          'Username atau password salah',
        );
      });

      test('wrong login with Indonesian backend detail stays credential error', () {
        // Backend now sends the ID copy directly.
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            statusCode: 401,
            data: {'detail': 'Username atau password salah'},
            requestOptions: RequestOptions(path: '/auth/login'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect(result, isNot(isA<UnauthorizedException>()));
        expect(
          (result as ApiException).message,
          'Username atau password salah',
        );
      });

      test('passes through server detail for non-401 errors', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 422,
            data: {'detail': 'Data gak valid. Cek isian kamu ya.'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect(
          (result as ApiException).message,
          'Data gak valid. Cek isian kamu ya.',
        );
      });

      test('returns NetworkException for connection timeout', () {
        final dioError = DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = client.handleError(dioError);
        expect(result, isA<NetworkException>());
      });

      test('returns NetworkException for receive timeout', () {
        final dioError = DioException(
          type: DioExceptionType.receiveTimeout,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = client.handleError(dioError);
        expect(result, isA<NetworkException>());
      });

      test('passes through unknown server detail unchanged', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 422,
            data: {'detail': 'Data gak valid. Cek isian kamu ya.'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Data gak valid. Cek isian kamu ya.');
      });

      test('passes through nested 500 detail.message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 500,
            data: {
              'detail': {
                'code': 'INTERNAL_ERROR',
                'message': 'Ada yang gak beres. Coba lagi ya.',
              }
            },
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect((result as ApiException).message, 'Ada yang gak beres. Coba lagi ya.');
      });

      test('returns generic message for 500 without detail', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 500,
            requestOptions: RequestOptions(path: '/test'),
            statusMessage: 'Internal Server Error',
          ),
          message: 'Internal Server Error',
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Ada yang gak beres. Coba lagi ya.');
      });

      test('returns generic ApiException for unknown error types', () {
        final result = client.handleError('Some random string');
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Ada yang gak beres. Coba lagi ya.');
      });

      test('returns ApiException for non-Dio Exception', () {
        final result = client.handleError(FormatException('bad format'));
        expect(result, isA<ApiException>());
      });

      test('passes through server detail even when non-401', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 400,
            data: {'detail': 'Email ini sudah terdaftar'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect((result as ApiException).message, 'Email ini sudah terdaftar');
      });

      test('returns generic message for empty detail', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 500,
            data: {},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect((result as ApiException).message, 'Ada yang gak beres. Coba lagi ya.');
      });

      test('uses copy key when server sends code', () {
        activeUiLocale = 'en-US';
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            statusCode: 401,
            data: {
              'detail': 'Wrong username or password',
              'code': 'err.credentials',
            },
            requestOptions: RequestOptions(path: '/auth/login'),
          ),
        );
        final result = client.handleError(dioError);
        expect((result as ApiException).message, 'Wrong username or password');
        activeUiLocale = 'id-ID';
      });
    });

    group('constructor', () {
      test('creates instance with secure storage', () {
        expect(client, isNotNull);
      });
    });

    group('streamPost error handling', () {
      test('returns a Stream', () {
        final stream = client.streamPost('/test/stream');
        expect(stream, isA<Stream<String>>());
      });
    });
  });
}
