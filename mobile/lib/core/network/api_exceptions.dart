import '../ui/copy_fallback.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException() : super(t('err.session'), statusCode: 401);
}

class NetworkException extends ApiException {
  NetworkException() : super(t('err.network'));
}
