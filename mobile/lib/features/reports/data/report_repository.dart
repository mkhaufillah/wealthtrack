import '../../../core/network/api_client.dart';
import '../models/report_model.dart';

class ReportRepository {
  final ApiClient _client;
  ReportRepository(this._client);

  Future<MonthlyReport> getMonthlyReport(String month) async {
    final res = await _client.get('/summaries/monthly', queryParams: {'month': month});
    return MonthlyReport.fromJson(res.data);
  }

  Future<HouseholdReport> getHouseholdReport({
    required String dateFrom,
    required String dateTo,
  }) async {
    final res = await _client.get('/summaries/household', queryParams: {
      'date_from': dateFrom,
      'date_to': dateTo,
    });
    return HouseholdReport.fromJson(res.data);
  }
}
