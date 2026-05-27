import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Mock [FlutterSecureStorage] that stores values in-memory.
class MockSecureStorage {
  final _store = <String, String>{};

  Future<void> saveToken(String token) async => _store['token'] = token;
  Future<String?> getToken() async => _store['token'];
  Future<void> clearToken() async => _store.remove('token');
  Future<void> clearAll() async => _store.clear();
}

/// A response-like data container for test API responses.
class MockResponse {
  final dynamic data;
  MockResponse(this.data);
}

/// Mock [ApiClient] that returns canned responses without real HTTP calls.
class MockApiClient {
  final Map<String, MockResponse> _getResponses = {};
  final Map<String, MockResponse> _postResponses = {};
  bool throwOnNext = false;
  Exception? nextError;
  int getCallCount = 0;
  int postCallCount = 0;

  void onGet(String path, dynamic data) => _getResponses[path] = MockResponse(data);
  void onPost(String path, dynamic data) => _postResponses[path] = MockResponse(data);

  Future<MockResponse> get(String path, {Map<String, dynamic>? queryParams}) async {
    getCallCount++;
    if (throwOnNext) {
      throwOnNext = false;
      throw nextError ?? Exception('Mock error');
    }
    return _getResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  Future<MockResponse> post(String path, {dynamic data}) async {
    postCallCount++;
    if (throwOnNext) {
      throwOnNext = false;
      throw nextError ?? Exception('Mock error');
    }
    return _postResponses[path] ?? MockResponse(<String, dynamic>{});
  }

  Exception handleError(dynamic e) => e is Exception ? e : Exception('Handled: $e');
}
