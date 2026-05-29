import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/report_repository.dart';
import '../models/report_model.dart';

class ReportState {
  final bool isLoading;
  final String? error;
  final MonthlyReport? monthly;
  final HouseholdReport? household;
  final String selectedMonth;
  final List<Map<String, dynamic>> householdTransactions;
  final List<MonthlyTrend> trend;
  final bool isTrendLoading;

  const ReportState({
    this.isLoading = false,
    this.error,
    this.monthly,
    this.household,
    this.selectedMonth = '',
    this.householdTransactions = const [],
    this.trend = const [],
    this.isTrendLoading = false,
  });

  ReportState copyWith({
    bool? isLoading,
    String? error,
    MonthlyReport? monthly,
    HouseholdReport? household,
    String? selectedMonth,
    List<Map<String, dynamic>>? householdTransactions,
    List<MonthlyTrend>? trend,
    bool? isTrendLoading,
  }) =>
      ReportState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        monthly: monthly ?? this.monthly,
        household: household ?? this.household,
        selectedMonth: selectedMonth ?? this.selectedMonth,
        householdTransactions: householdTransactions ?? this.householdTransactions,
        trend: trend ?? this.trend,
        isTrendLoading: isTrendLoading ?? this.isTrendLoading,
      );
}

class ReportNotifier extends StateNotifier<ReportState> {
  final ReportRepository _repo;
  final ApiClient _api;
  ReportNotifier(this._repo, this._api) : super(const ReportState());

  void selectMonth(String month) {
    state = state.copyWith(selectedMonth: month);
    load(month);
  }

  Future<void> load(String month) async {
    state = state.copyWith(isLoading: true, error: null, selectedMonth: month);
    try {
      final monthly = await _repo.getMonthlyReport(month);
      state = state.copyWith(isLoading: false, monthly: monthly);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<void> loadHousehold({required String dateFrom, required String dateTo}) async {
    try {
      final hh = await _repo.getHouseholdReport(dateFrom: dateFrom, dateTo: dateTo);
      state = state.copyWith(household: hh);
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
    }
    try {
      final txns = await _repo.getHouseholdTransactions(
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      final data = (txns['data'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      state = state.copyWith(householdTransactions: data);
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
    }
  }

  Future<void> loadTrend({required String monthFrom, required String monthTo}) async {
    state = state.copyWith(isTrendLoading: true);
    try {
      final trend = await _repo.getMonthlyTrend(monthFrom: monthFrom, monthTo: monthTo);
      state = state.copyWith(trend: trend, isTrendLoading: false);
    } catch (_) {
      state = state.copyWith(isTrendLoading: false);
    }
  }
}

final reportProvider = StateNotifierProvider<ReportNotifier, ReportState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ReportNotifier(ReportRepository(api), api);
});
