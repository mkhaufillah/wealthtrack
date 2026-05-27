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
  final String selectedMonth; // "2026-05" format

  const ReportState({
    this.isLoading = false,
    this.error,
    this.monthly,
    this.household,
    this.selectedMonth = '',
  });

  ReportState copyWith({
    bool? isLoading,
    String? error,
    MonthlyReport? monthly,
    HouseholdReport? household,
    String? selectedMonth,
  }) =>
      ReportState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        monthly: monthly ?? this.monthly,
        household: household ?? this.household,
        selectedMonth: selectedMonth ?? this.selectedMonth,
      );
}

class ReportNotifier extends StateNotifier<ReportState> {
  final ReportRepository _repo;
  ReportNotifier(this._repo) : super(const ReportState());

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
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadHousehold({required String dateFrom, required String dateTo}) async {
    try {
      final hh = await _repo.getHouseholdReport(dateFrom: dateFrom, dateTo: dateTo);
      state = state.copyWith(household: hh);
    } catch (_) {
      // Household is optional — don't block the UI
    }
  }
}

final reportProvider = StateNotifierProvider<ReportNotifier, ReportState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ReportNotifier(ReportRepository(api));
});
