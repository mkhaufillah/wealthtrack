import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/token_model.dart';
import '../models/user_model.dart';

class AuthRepository {
  final ApiClient _client;
  AuthRepository(this._client);

  Future<TokenModel> login(String username, String password) async {
    try {
      final res = await _client.post('/auth/login', data: {'username': username, 'password': password});
      return TokenModel.fromJson(res.data);
    } catch (e) { throw _client.handleError(e); }
  }

  Future<UserModel> register(String username, String displayName, String password) async {
    try {
      final res = await _client.post('/auth/register', data: {'username': username, 'display_name': displayName, 'password': password});
      return UserModel.fromJson(res.data);
    } catch (e) { throw _client.handleError(e); }
  }

  Future<UserModel> getMe() async {
    try {
      final res = await _client.get('/auth/me');
      return UserModel.fromJson(res.data);
    } catch (e) { throw _client.handleError(e); }
  }
}