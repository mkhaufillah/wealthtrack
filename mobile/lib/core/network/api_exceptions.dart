class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException() : super('Sesi habis. Masuk lagi ya.', statusCode: 401);
}

class NetworkException extends ApiException {
  NetworkException() : super('Gak ada internet. Cek koneksi, coba lagi.');
}
