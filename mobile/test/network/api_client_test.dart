import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/network/api_exceptions.dart';
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
            data: {'detail': 'Invalid username or password'},
            requestOptions: RequestOptions(path: '/auth/login'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect(result, isNot(isA<UnauthorizedException>()));
        expect(
          (result as ApiException).message,
          'Username atau password salah.',
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

      test('maps unrecognized backend error to generic message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 422,
            data: {'detail': 'Unknown validation error'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Ada yang gak beres. Coba lagi ya.');
      });

      test('returns generic message for 500', () {
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

      test('maps known error messages to friendly text', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 400,
            data: {'detail': 'Invalid email or password'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        expect((result as ApiException).message, 'Username atau password salah.');
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
