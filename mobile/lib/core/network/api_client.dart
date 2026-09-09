import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../constants.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';

/// Server-driven error copy: the backend owns user-facing messages in Bahasa.
/// This client only handles transport-level failures (no network, expired
/// session). Any `detail` the server sends is passed through as-is.

String _rawDetail(DioException error) {
  final detail = error.response?.data;
  if (detail is Map && detail.containsKey('detail')) {
    final d = detail['detail'];
    if (d is List) {
      return d.isNotEmpty ? (d[0]['msg']?.toString() ?? '') : '';
    }
    if (d is Map) {
      final nested = d['message'] ?? d['detail'];
      if (nested != null) return nested.toString();
    }
    return d.toString();
  }
  if (detail is String && detail.isNotEmpty) {
    return detail;
  }
  // Server owns the message. Dio's own English text is never user-facing.
  return '';
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
        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.contains('/auth/login')) {
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

  Future<Response> put(String path, {dynamic data, Map<String, dynamic>? queryParams}) =>
      _dio.put(path, data: data, queryParameters: queryParams);

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
  /// When the caller cancels the subscription, the underlying HTTP request
  /// is aborted to prevent resource leaks.
  Stream<String> streamPost(String path, {dynamic data, CancelToken? cancelToken}) {
    final cancelTokenForRequest = cancelToken ?? CancelToken();
    final streamController = StreamController<String>(
      onCancel: () {
        if (!cancelTokenForRequest.isCancelled) {
          cancelTokenForRequest.cancel('Stream cancelled by client');
        }
        developer.log('SSE stream cancelled, request aborted');
      },
    );

    _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancelTokenForRequest,
    ).then((response) {
      // Guard: if already cancelled before response arrived
      if (cancelTokenForRequest.isCancelled) return;
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
              unawaited(streamController.close());
              return;
            }
            try {
              final json = jsonDecode(payload) as Map<String, dynamic>;
              if (json.containsKey('error')) {
                streamController.addError(Exception(json['error']));
                unawaited(streamController.close());
                return;
              }
              final token = json['token'] as String?;
              if (token != null && token.isNotEmpty) {
                streamController.add(token);
              }
            } catch (e) {
              developer.log('SSE parse error: $e');
            }
          }
        },
        onDone: () => unawaited(streamController.close()),
        onError: (e) {
          if (!streamController.isClosed) {
            streamController.addError(e);
            unawaited(streamController.close());
          }
        },
        cancelOnError: false,
      );
    }).catchError((e) {
      if (cancelTokenForRequest.isCancelled) return; // Intentional cancellation
      if (!streamController.isClosed) {
        streamController.addError(e);
        unawaited(streamController.close());
      }
    });

    return streamController.stream;
  }

  Exception handleError(dynamic error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return NetworkException();
      }

      final rawMsg = _rawDetail(error);
      final isLogin = error.requestOptions.path.contains('/auth/login');

      // 401 on non-login = expired/revoked JWT (client-side decision).
      if (error.response?.statusCode == 401 && !isLogin) {
        return UnauthorizedException();
      }

      // Server owns the message text (Bahasa). Pass it through as-is.
      if (rawMsg.isNotEmpty) {
        return ApiException(rawMsg, statusCode: error.response?.statusCode);
      }

      // No detail from server: use transport-level fallbacks.
      if (error.response?.statusCode == 429) {
        return ApiException('Kebanyakan request. Tunggu sebentar ya.');
      }
      return ApiException('Ada yang gak beres. Coba lagi ya.');
    }

    return ApiException('Ada yang gak beres. Coba lagi ya.');
  }
}
