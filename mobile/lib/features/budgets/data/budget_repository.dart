import '../../../core/network/api_client.dart';
import '../models/budget_model.dart';

class BudgetRepository {
  final ApiClient _client;
  BudgetRepository(this._client);

  Future<List<BudgetSummaryItem>> getSummary(String month) async {
    final res = await _client.get('/budgets/summary', queryParams: {'month': month});
    return (res.data as List).map((e) => BudgetSummaryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BudgetModel> create(Map<String, dynamic> data) async {
    final res = await _client.post('/budgets', data: data);
    return BudgetModel.fromJson(res.data);
  }

  Future<void> delete(int id) async {
    await _client.delete('/budgets/$id');
  }
}
