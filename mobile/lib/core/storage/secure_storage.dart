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

  Future<void> deleteSecure(String key) =>
      _storage.delete(key: key);

  /// Which account the stored vault key / cached user currently belongs to.
  /// Used to stop a key from one account being handed to another account on
  /// the same device.
  static const _currentUserIdKey = 'current_user_id';

  Future<void> saveCurrentUserId(int id) =>
      _storage.write(key: _currentUserIdKey, value: '$id');

  Future<int?> getCurrentUserId() async {
    final raw = await _storage.read(key: _currentUserIdKey);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> clearCurrentUserId() =>
      _storage.delete(key: _currentUserIdKey);
}
