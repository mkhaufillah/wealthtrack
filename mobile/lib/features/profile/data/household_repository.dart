import '../../../core/network/api_client.dart';

class HouseholdRepository {
  final ApiClient _client;
  HouseholdRepository(this._client);

  Future<Map<String, dynamic>> getMyHousehold() async {
    try {
      final res = await _client.get('/households/me');
      return res.data;
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<void> createHousehold(String name) async {
    try {
      await _client.post('/households', data: {'name': name});
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<Map<String, dynamic>> joinHousehold(String inviteCode) async {
    try {
      final res = await _client.post('/households/join', data: {'invite_code': inviteCode});
      return res.data;
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<String> getInviteCode() async {
    try {
      final res = await _client.get('/households/invite-code');
      return res.data['invite_code'] as String;
    } catch (e) {
      throw _client.handleError(e);
    }
  }
}
