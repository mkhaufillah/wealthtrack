import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants.dart';

class SecureStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _storage.write(key: AppConstants.tokenKey, value: token);

  Future<String?> getToken() =>
      _storage.read(key: AppConstants.tokenKey);

  Future<void> clearToken() =>
      _storage.delete(key: AppConstants.tokenKey);

  Future<void> saveUser(String userJson) =>
      _storage.write(key: AppConstants.userKey, value: userJson);

  Future<String?> getUser() =>
      _storage.read(key: AppConstants.userKey);

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  Future<void> saveSecure(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> getSecure(String key) =>
      _storage.read(key: key);
}
