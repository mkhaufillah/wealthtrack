import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import '../constants.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';

/// Maps raw backend error strings to user-friendly messages.
/// Unknown/unmatched errors fall back to a generic "Something went wrong."
const _friendlyErrors = <String, String>{
  'invalid email or password': 'Email or password is incorrect.',
  'email already registered': 'This email is already registered.',
  'account not found': 'Account not found.',
  'user not found': 'Account not found.',
  'invalid token': 'Session expired. Please login again.',
  'could not determine amount or category': 'Something went wrong. Please try again.',
  'ocr rate limit': 'Please wait before uploading another receipt.',
  'you already have an ocr job': 'Please wait for the current receipt to finish processing.',
  'vision api error': 'Something went wrong. Please try again.',
  'vision api timed out': 'Something went wrong. Please try again.',
  'image too large': 'Image is too large. Max 10 MB.',
  'unsupported image format': 'Unsupported image format. Use JPG or PNG.',
};

/// Returns a user-friendly message for a given error string.
String _friendly(String raw) {
  final lower = raw.toLowerCase();
  for (final entry in _friendlyErrors.entries) {
    if (lower.contains(entry.key)) {
      return entry.value;
    }
  }
  return 'Something went wrong. Please try again.';
}

class ApiClient {
  late final Dio _dio;
  final SecureStorage _storage;

  ApiClient({required SecureStorage storage})
      : _storage = storage {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await _storage.clearToken();
        }
        handler.next(error);
      },
    ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) =>
      _dio.get(path, queryParameters: queryParams);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);

  Future<Response> download(String path, String savePath) =>
      _dio.download(path, savePath);

  Future<Response> uploadFile(String path, String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    return _dio.post(path, data: formData);
  }

  /// POST to an SSE streaming endpoint. Returns a stream of token strings.
  Stream<String> streamPost(String path, {dynamic data}) {
    final streamController = StreamController<String>();

    _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(responseType: ResponseType.stream),
    ).then((response) {
      final body = response.data as ResponseBody;
      body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final payload = line.substring(6).trim();
            if (payload == '[DONE]') {
              streamController.close();
              return;
            }
            try {
              final json = jsonDecode(payload) as Map<String, dynamic>;
              if (json.containsKey('error')) {
                streamController.addError(Exception(json['error']));
                streamController.close();
                return;
              }
              final token = json['token'] as String?;
              if (token != null && token.isNotEmpty) {
                streamController.add(token);
              }
            } catch (_) {
              // Ignore malformed SSE events
            }
          }
        },
        onDone: () => streamController.close(),
        onError: (e) {
          streamController.addError(e);
          streamController.close();
        },
      );
    }).catchError((e) {
      streamController.addError(e);
      streamController.close();
    });

    return streamController.stream;
  }

  Exception handleError(dynamic error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      if (error.response?.statusCode == 401) return UnauthorizedException();
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return NetworkException();
      }

      // Extract message from backend response
      final detail = error.response?.data;
      String rawMsg;
      if (detail is Map && detail.containsKey('detail')) {
        final d = detail['detail'];
        if (d is List) {
          // FastAPI 422 validation error — extract first message
          rawMsg = d.isNotEmpty ? (d[0]['msg']?.toString() ?? '') : '';
        } else {
          rawMsg = d.toString();
        }
      } else {
        rawMsg = error.message ?? '';
      }

      if (rawMsg.isEmpty) {
        return ApiException('Something went wrong. Please try again.');
      }

      // Rate limit (429)
      if (error.response?.statusCode == 429) {
        return ApiException('Too many requests. Please wait a moment.');
      }

      return ApiException(_friendly(rawMsg));
    }

    return ApiException('Something went wrong. Please try again.');
  }
}
