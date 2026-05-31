import '../../../core/network/api_client.dart';
import '../models/token_model.dart';
import '../models/user_model.dart';

class AuthRepository {
  final ApiClient _client;
  AuthRepository(this._client);

  Future<void> sendOtp(String email) async {
    try {
      await _client.post('/auth/send-otp', data: {
        'email': email,
      });
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<TokenModel> login(String username, String password) async {
    try {
      final res = await _client.post('/auth/login', data: {
        'username': username,
        'password': password,
      });
      return TokenModel.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<UserModel> register(
      String email, String otpCode, String username, String displayName, String password) async {
    try {
      final res = await _client.post('/auth/register', data: {
        'email': email,
        'otp_code': otpCode,
        'username': username,
        'display_name': displayName,
        'password': password,
      });
      return UserModel.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<UserModel> getMe() async {
    try {
      final res = await _client.get('/auth/me');
      return UserModel.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<UserModel> updateProfile(String displayName, {int? cycleStartDay, String? email}) async {
    try {
      final data = <String, dynamic>{'display_name': displayName};
      if (cycleStartDay != null) data['cycle_start_day'] = cycleStartDay;
      if (email != null) data['email'] = email;
      final res = await _client.put('/auth/me', data: data);
      return UserModel.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    try {
      await _client.put('/auth/password', data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _client.delete('/auth/me');
    } catch (e) {
      throw _client.handleError(e);
    }
  }
}
