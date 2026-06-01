import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_exceptions.dart';

void main() {
  group('ApiException', () {
    test('stores message and statusCode', () {
      final exc = ApiException('Not found', statusCode: 404);
      expect(exc.message, 'Not found');
      expect(exc.statusCode, 404);
    });

    test('toString returns just the message', () {
      final exc = ApiException('Email or password is incorrect.', statusCode: 401);
      expect(exc.toString(), 'Email or password is incorrect.');
    });

    test('toString without status code', () {
      final exc = ApiException('Something went wrong. Please try again.');
      expect(exc.toString(), 'Something went wrong. Please try again.');
    });

    test('is an Exception', () {
      final exc = ApiException('test');
      expect(exc, isA<Exception>());
    });

    test('can be thrown and caught', () {
      expect(
        () => throw ApiException('Boom'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('UnauthorizedException', () {
    test('extends ApiException with status 401', () {
      final exc = UnauthorizedException();
      expect(exc, isA<ApiException>());
      expect(exc.statusCode, 401);
      expect(exc.message, 'Session expired. Please login again.');
    });

    test('toString returns friendly message', () {
      final exc = UnauthorizedException();
      expect(exc.toString(), 'Session expired. Please login again.');
    });

    test('can be thrown and caught as ApiException', () {
      expect(
        () => throw UnauthorizedException(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('NetworkException', () {
    test('extends ApiException', () {
      final exc = NetworkException();
      expect(exc, isA<ApiException>());
      expect(exc.statusCode, isNull);
      expect(exc.message, 'No internet connection. Please check and try again.');
    });

    test('toString returns friendly message', () {
      final exc = NetworkException();
      expect(exc.toString(), 'No internet connection. Please check and try again.');
    });

    test('can be thrown and caught', () {
      expect(
        () => throw NetworkException(),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
