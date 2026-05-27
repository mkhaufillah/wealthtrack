import '../../../core/network/api_client.dart';

class HouseholdRepository {
  final ApiClient _client;
  HouseholdRepository(this._client);

  Future<Map<String, dynamic>> getMyHousehold() async {
    final res = await _client.get('/households/me');
    return res.data;
  }

  Future<void> createHousehold(String name) async {
    await _client.post('/households', data: {'name': name});
  }

  Future<Map<String, dynamic>> joinHousehold(String inviteCode) async {
    final res = await _client.post('/households/join', data: {'invite_code': inviteCode});
    return res.data;
  }

  Future<String> getInviteCode() async {
    final res = await _client.get('/households/invite-code');
    return res.data['invite_code'] as String;
  }
}
