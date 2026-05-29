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

      test('returns UnauthorizedException for 401', () {
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

      test('returns ApiException with error detail from response', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 422,
            data: {'detail': 'Validation failed'},
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = client.handleError(dioError);
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Validation failed');
        expect(apiExc.statusCode, 422);
      });

      test('returns ApiException with status code for non-detailed error', () {
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
        expect(apiExc.message, 'Internal Server Error');
        expect(apiExc.statusCode, 500);
      });

      test('returns generic ApiException for unknown error types', () {
        final result = client.handleError('Some random string');
        expect(result, isA<ApiException>());
        final apiExc = result as ApiException;
        expect(apiExc.message, 'Unexpected error occurred');
      });

      test('returns ApiException for non-Dio Exception', () {
        final result = client.handleError(FormatException('bad format'));
        expect(result, isA<ApiException>());
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
