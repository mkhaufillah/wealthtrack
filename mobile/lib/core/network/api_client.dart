import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../constants.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';

/// Maps raw backend error strings to user-friendly messages.
/// Unknown/unmatched errors fall back to a generic "Something went wrong."
const _friendlyErrors = <String, String>{
  'invalid email or password': 'Email atau password salah.',
  'invalid username or password': 'Email atau password salah.',
  'email already registered': 'Email ini sudah terdaftar.',
  'email already in use': 'Email ini sudah terdaftar.',
  'username already exists': 'Username sudah kepakai.',
  'account not found': 'Akun gak ketemu.',
  'user not found': 'Akun gak ketemu.',
  'invalid token': 'Sesi habis. Masuk lagi ya.',
  'invalid otp': 'Kode OTP salah.',
  'otp already used': 'Kode OTP sudah dipakai.',
  'otp has expired': 'Kode OTP kadaluarsa. Minta yang baru ya.',
  'no otp sent': 'Belum ada kode OTP. Minta dulu ya.',
  'current password is incorrect': 'Sandi sekarang salah.',
  'already in a household': 'Kamu sudah di keluarga.',
  'invalid invite code': 'Kode undangan gak valid.',
  'not a member of any household': 'Belum gabung keluarga.',
  'could not determine amount or category': 'Ada yang gak beres. Coba lagi ya.',
  'ocr rate limit': 'Tunggu sebentar sebelum unggah struk lagi.',
  'you already have an ocr job': 'Struk sebelumnya masih diproses, tunggu ya.',
  'vision api error': 'Ada yang gak beres. Coba lagi ya.',
  'vision api timed out': 'Ada yang gak beres. Coba lagi ya.',
  'image too large': 'Fotonya kegedean. Maks 10 MB.',
  'unsupported image format': 'Format foto gak didukung. Pakai JPG atau PNG.',
  'could not detect file type': 'Tipe file tidak dikenali.',
  'tipe file tidak dikenali': 'Tipe file tidak dikenali.',
};

/// Returns a user-friendly message for a given error string.
String _friendly(String raw) {
  final lower = raw.toLowerCase();
  for (final entry in _friendlyErrors.entries) {
    if (lower.contains(entry.key)) {
      return entry.value;
    }
  }
  return 'Ada yang gak beres. Coba lagi ya.';
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
        return ApiException('Ada yang gak beres. Coba lagi ya.');
      }

      // Rate limit (429)
      if (error.response?.statusCode == 429) {
        return ApiException('Kebanyakan request. Tunggu sebentar ya.');
      }

      return ApiException(_friendly(rawMsg));
    }

    return ApiException('Ada yang gak beres. Coba lagi ya.');
  }
}
