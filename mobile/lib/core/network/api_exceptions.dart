class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UnauthorizedException extends ApiException {
  UnauthorizedException() : super('Unauthorized', statusCode: 401);
}

class NetworkException extends ApiException {
  NetworkException() : super('Network error — check your connection');
}
