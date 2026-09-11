import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../constants.dart';
import '../storage/secure_storage.dart';
import '../vault/vault_store.dart';
import '../ui/copy_fallback.dart';
import 'api_exceptions.dart';

/// Server-driven error copy: the backend owns user-facing messages in Bahasa.
/// This client only handles transport-level failures (no network, expired
/// session). Any `detail` the server sends is passed through as-is.

bool _looksLikeHtml(String raw) {
  final s = raw.trim().toLowerCase();
  return s.contains('<html') ||
      s.contains('<!doctype') ||
      s.contains('<body') ||
      s.contains('<head');
}

String _statusCopy(int? status) {
  return switch (status) {
    403 => t('err.forbidden'),
    404 => t('err.not_found'),
    502 || 503 || 504 => t('err.unavailable'),
    _ => t('err.generic'),
  };
}

String _rawCode(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['code'] is String) {
    return data['code'] as String;
  }
  return '';
}

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

  /// Fired when a response says our vault key is unusable
  /// (``err.vault_required`` / ``err.vault_pending``). Wired to the auth
  /// notifier so the app re-checks the vault gate.
  void Function()? onVaultRequired;

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
        options.headers['X-Locale'] = activeUiLocale;
        final dek = await VaultStore.getDekB64(_storage);
        if (dek != null && dek.isNotEmpty) {
          options.headers['X-Vault-Key'] = dek;
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.contains('/auth/login')) {
          await _storage.clearToken();
        }
        // A *data* endpoint refused us for lack of a usable key. Vault gate
        // endpoints answer ``err.vault_pending`` (404) for "nothing here yet"
        // — that is not a broken key, so ignore it and never wipe a key we
        // actually hold (that bug locked owners out of their own vault).
        final response = error.response;
        final body = response?.data;
        if (response?.statusCode == 403 &&
            body is Map &&
            (body['code'] ?? body['detail']) == 'err.vault_required' &&
            !error.requestOptions.path.startsWith('/households/vault/')) {
          onVaultRequired?.call();
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
      final code = _rawCode(error);
      final isLogin = error.requestOptions.path.contains('/auth/login');

      // 401 on non-login = expired/revoked JWT (client-side decision).
      if (error.response?.statusCode == 401 && !isLogin) {
        return UnauthorizedException();
      }

      if (code.isNotEmpty) {
        return ApiException(t(code), statusCode: error.response?.statusCode);
      }

      // Server-localized detail (or legacy ID string). Never dump HTML.
      if (rawMsg.isNotEmpty && !_looksLikeHtml(rawMsg) && rawMsg.length < 280) {
        return ApiException(rawMsg, statusCode: error.response?.statusCode);
      }

      if (error.response?.statusCode == 429) {
        return ApiException(t('err.rate_limit'));
      }
      return ApiException(_statusCopy(error.response?.statusCode));
    }

    return ApiException(t('err.generic'));
  }
}
