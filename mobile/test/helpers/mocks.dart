import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import 'package:wealthtrack/features/auth/data/auth_repository.dart';
import 'package:wealthtrack/features/auth/models/token_model.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';

/// Prevent platform channel errors in test environment.
void initTestSecureStorage() {
  FlutterSecureStorage.setMockInitialValues({});
}

/// Mock [FlutterSecureStorage] that stores values in-memory.
class MockSecureStorage extends SecureStorage {
  final _store = <String, String>{};

  @override
  Future<void> saveToken(String token) async => _store['token'] = token;
  @override
  Future<String?> getToken() async => _store['token'];
  @override
  Future<void> clearToken() async => _store.remove('token');
  @override
  Future<void> clearAll() async => _store.clear();
}

/// A lightweight Dio-like response for test assertions.
class MockResponse extends Response {
  MockResponse(dynamic data)
      : super(data: data, requestOptions: RequestOptions(path: ''));
}

/// Mock [ApiClient] that returns canned responses without real HTTP calls.
class MockApiClient extends ApiClient {
  final Map<String, MockResponse> _getResponses = {};
  final Map<String, MockResponse> _postResponses = {};
  final Map<String, MockResponse> _putResponses = {};
  final Set<String> _deletePaths = {};
  final Map<String, StreamController<String>> _streamPostControllers = {};

  MockApiClient() : super(storage: MockSecureStorage());

  void onGet(String path, dynamic data) =>
      _getResponses[path] = MockResponse(data);
  void onPost(String path, dynamic data) =>
      _postResponses[path] = MockResponse(data);
  void onPut(String path, dynamic data) =>
      _putResponses[path] = MockResponse(data);
  void onDelete(String path) => _deletePaths.add(path);

  /// Register a [StreamController] for a streaming POST endpoint.
  /// The test can then add tokens to the controller to simulate SSE events.
  void onStreamPost(String path, StreamController<String> controller) =>
      _streamPostControllers[path] = controller;

  @override
  Future<Response> get(String path,
      {Map<String, dynamic>? queryParams}) async {
    return _getResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  @override
  Future<Response> post(String path, {dynamic data}) async {
    return _postResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  @override
  Future<Response> put(String path, {dynamic data}) async {
    return _putResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  @override
  Future<Response> delete(String path) async {
    // Simulate 204 No Content
    return MockResponse(null);
  }

  @override
  Stream<String> streamPost(String path, {dynamic data}) {
    final controller = _streamPostControllers[path];
    if (controller != null) return controller.stream;
    return const Stream.empty();
  }

  @override
  Exception handleError(dynamic e) =>
      e is Exception ? e : Exception('Handled: $e');
}

/// Mock [AuthRepository] that returns canned data without real API calls.
class MockAuthRepository extends AuthRepository {
  MockAuthRepository() : super(MockApiClient());

  @override
  Future<TokenModel> login(String username, String password) async {
    return TokenModel(accessToken: 'mock', tokenType: 'bearer', expiresIn: 3600);
  }

  @override
  Future<UserModel> register(
      String email, String otpCode, String username, String displayName, String password) async {
    return UserModel(id: 1, username: username, displayName: displayName, role: 'user', email: email);
  }

  @override
  Future<UserModel> getMe() async {
    return UserModel(id: 1, username: 'mock', displayName: 'Mock', role: 'user', email: 'mock@test.com');
  }

  @override
  Future<UserModel> updateProfile(String displayName, {int? cycleStartDay, String? email}) async {
    return UserModel(id: 1, username: 'mock', displayName: displayName, role: 'user', cycleStartDay: cycleStartDay ?? 1, email: email ?? '');
  }

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    return;
  }

  @override
  Future<void> deleteAccount() async {
    return;
  }
}
