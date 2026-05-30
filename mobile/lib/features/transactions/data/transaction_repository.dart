import '../../../core/network/api_client.dart';
import '../models/transaction_model.dart';

class TransactionRepository {
  final ApiClient _client;
  TransactionRepository(this._client);

  Future<Map<String, dynamic>> list({
    int page = 1,
    int perPage = 50,
    String? type,
    int? categoryId,
    String? dateFrom,
    String? dateTo,
    String? sort,
    String? q,
    List<int>? categoryIds,
  }) async {
    final params = <String, dynamic>{'page': page, 'per_page': perPage};
    if (sort != null) params['sort'] = sort;
    if (type != null) params['type'] = type;
    if (categoryId != null) params['category_id'] = categoryId;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params['category_ids'] = categoryIds.join(',');
    }
    try {
      final res = await _client.get('/transactions', queryParams: params);
      final txns = (res.data['data'] as List).map((e) => TransactionModel.fromJson(e)).toList();
      return {'transactions': txns, 'total': res.data['meta']['total'] as int};
    } catch (e) { throw _client.handleError(e); }
  }

  Future<TransactionModel> create(Map<String, dynamic> data) async {
    try { final res = await _client.post('/transactions', data: data); return TransactionModel.fromJson(res.data); }
    catch (e) { throw _client.handleError(e); }
  }

  Future<TransactionModel> update(int id, Map<String, dynamic> data) async {
    try { final res = await _client.put('/transactions/$id', data: data); return TransactionModel.fromJson(res.data); }
    catch (e) { throw _client.handleError(e); }
  }

  Future<void> delete(int id) async {
    try { await _client.delete('/transactions/$id'); }
    catch (e) { throw _client.handleError(e); }
  }

  Future<TransactionModel> transferOwner(int id, int userId) async {
    try {
      final res = await _client.put('/transactions/$id/owner', data: {'user_id': userId});
      return TransactionModel.fromJson(res.data);
    } catch (e) { throw _client.handleError(e); }
  }

  Future<Map<String, dynamic>> transferBalance({
    required String date,
    required List<Map<String, dynamic>> transfers,
  }) async {
    try {
      final res = await _client.post('/transactions/transfer', data: {
        'date': date,
        'transfers': transfers,
      });
      return res.data as Map<String, dynamic>;
    } catch (e) { throw _client.handleError(e); }
  }
}