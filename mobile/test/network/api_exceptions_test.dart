import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_exceptions.dart';

void main() {
  group('ApiException', () {
    test('stores message and statusCode', () {
      final exc = ApiException('Not found', statusCode: 404);
      expect(exc.message, 'Not found');
      expect(exc.statusCode, 404);
    });

    test('toString includes status code when provided', () {
      final exc = ApiException('Not found', statusCode: 404);
      expect(exc.toString(), 'ApiException(404): Not found');
    });

    test('toString omits status code when null', () {
      final exc = ApiException('Generic error');
      expect(exc.toString(), 'ApiException: Generic error');
    });

    test('toString with zero status code', () {
      final exc = ApiException('Unknown', statusCode: 0);
      expect(exc.toString(), 'ApiException(0): Unknown');
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
      expect(exc.message, 'Unauthorized');
    });

    test('toString shows 401 status', () {
      final exc = UnauthorizedException();
      expect(exc.toString(), 'ApiException(401): Unauthorized');
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
      expect(exc.message, 'Network error — check your connection');
    });

    test('toString omits status code', () {
      final exc = NetworkException();
      expect(exc.toString(), 'ApiException: Network error — check your connection');
    });

    test('can be thrown and caught', () {
      expect(
        () => throw NetworkException(),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
