import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wealthtrack/core/network/api_client.dart';
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

/// A response-like data container for test API responses.
class MockResponse {
  final dynamic data;
  MockResponse(this.data);
}

/// Mock [ApiClient] that returns canned responses without real HTTP calls.
class MockApiClient extends ApiClient {
  final Map<String, MockResponse> _getResponses = {};
  final Map<String, MockResponse> _postResponses = {};
  bool throwOnNext = false;
  Exception? nextError;
  int getCallCount = 0;
  int postCallCount = 0;

  MockApiClient() : super(storage: MockSecureStorage());

  void onGet(String path, dynamic data) => _getResponses[path] = MockResponse(data);
  void onPost(String path, dynamic data) => _postResponses[path] = MockResponse(data);

  @override
  Future<MockResponse> get(String path, {Map<String, dynamic>? queryParams}) async {
    getCallCount++;
    return _getResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  @override
  Future<MockResponse> post(String path, {dynamic data}) async {
    postCallCount++;
    return _postResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  @override
  Exception handleError(dynamic e) => e is Exception ? e : Exception('Handled: $e');
}

/// Mock [AuthRepository] that returns canned data without real API calls.
class MockAuthRepository extends AuthRepository {
  MockAuthRepository() : super(MockApiClient());

  @override
  Future<TokenModel> login(String username, String password) async {
    return TokenModel(accessToken: 'mock', tokenType: 'bearer', expiresIn: 3600);
  }

  @override
  Future<UserModel> register(String username, String displayName, String password) async {
    return UserModel(id: 1, username: username, displayName: displayName, role: 'user');
  }

  @override
  Future<UserModel> getMe() async {
    return UserModel(id: 1, username: 'mock', displayName: 'Mock', role: 'user');
  }
}
