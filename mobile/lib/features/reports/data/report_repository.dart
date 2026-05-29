import '../../../core/network/api_client.dart';
import '../models/report_model.dart';

class ReportRepository {
  final ApiClient _client;
  ReportRepository(this._client);

  Future<MonthlyReport> getMonthlyReport(String month) async {
    try {
      final res = await _client.get('/summaries/monthly', queryParams: {'month': month});
      return MonthlyReport.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<HouseholdReport> getHouseholdReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      final res = await _client.get('/summaries/household', queryParams: {
        'date_from': dateFrom,
        'date_to': dateTo,
      });
      return HouseholdReport.fromJson(res.data);
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<Map<String, dynamic>> getHouseholdTransactions({
    required String dateFrom,
    required String dateTo,
    int perPage = 100,
  }) async {
    try {
      final res = await _client.get('/transactions/household', queryParams: {
        'per_page': perPage,
        'date_from': dateFrom,
        'date_to': dateTo,
      });
      return res.data;
    } catch (e) {
      throw _client.handleError(e);
    }
  }

  Future<List<MonthlyTrend>> getMonthlyTrend({
    required String monthFrom,
    required String monthTo,
  }) async {
    try {
      final res = await _client.get('/summaries/monthly', queryParams: {
        'month_from': monthFrom,
        'month_to': monthTo,
      });
      return (res.data as List).map((e) => MonthlyTrend.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw _client.handleError(e);
    }
  }
}
