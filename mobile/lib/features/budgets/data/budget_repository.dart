import '../../../core/network/api_client.dart';
import '../models/budget_model.dart';

class BudgetSummaryResult {
  final List<BudgetSummaryItem> items;
  final List<UnbudgetedExpense> uncategorizedExpenses;
  BudgetSummaryResult(this.items, this.uncategorizedExpenses);
}

class BudgetRepository {
  final ApiClient _client;
  BudgetRepository(this._client);

  Future<BudgetSummaryResult> getSummary(String month, {String? dateFrom, String? dateTo}) async {
    final queryParams = <String, String>{
      'month': month,
      'use_cycle': 'true',
    };
    if (dateFrom != null) queryParams['d_from_override'] = dateFrom;
    if (dateTo != null) queryParams['d_to_override'] = dateTo;
    final res = await _client.get('/budgets/summary', queryParams: queryParams);
    final data = res.data as Map<String, dynamic>;
    return BudgetSummaryResult(
      (data['items'] as List).map((e) => BudgetSummaryItem.fromJson(e as Map<String, dynamic>)).toList(),
      (data['uncategorized_expenses'] as List?)?.map((e) => UnbudgetedExpense.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }

  Future<BudgetModel> create(Map<String, dynamic> data) async {
    try {
      final res = await _client.post('/budgets', data: data);
      return BudgetModel.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.delete('/budgets/$id');
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<BudgetSuggestionResponse> getSuggestions(String month, {int numCycles = 3}) async {
    final res = await _client.get('/budgets/suggestions', queryParams: {
      'month': month,
      'num_cycles': numCycles.toString(),
    });
    return BudgetSuggestionResponse.fromJson(res.data as Map<String, dynamic>);
  }
}
