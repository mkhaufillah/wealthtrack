import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/budget_repository.dart';
import '../models/budget_model.dart';

class BudgetState {
  final bool isLoading;
  final String? error;
  final List<BudgetSummaryItem> items;
  final List<UnbudgetedExpense> uncategorizedExpenses;
  final String month;
  final int viewBalance;
  final int totalIncome;

  const BudgetState({
    this.isLoading = false,
    this.error,
    this.items = const [],
    this.uncategorizedExpenses = const [],
    this.month = '',
    this.viewBalance = 0,
    this.totalIncome = 0,
  });

  BudgetState copyWith({
    bool? isLoading,
    String? error,
    List<BudgetSummaryItem>? items,
    List<UnbudgetedExpense>? uncategorizedExpenses,
    String? month,
    int? viewBalance,
    int? totalIncome,
  }) =>
      BudgetState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        items: items ?? this.items,
        uncategorizedExpenses: uncategorizedExpenses ?? this.uncategorizedExpenses,
        month: month ?? this.month,
        viewBalance: viewBalance ?? this.viewBalance,
        totalIncome: totalIncome ?? this.totalIncome,
      );
}

class BudgetNotifier extends StateNotifier<BudgetState> {
  final BudgetRepository _repo;
  final ApiClient _api;
  String? _lastDateFrom;
  String? _lastDateTo;

  BudgetNotifier(this._repo, this._api) : super(const BudgetState());

  Future<void> load(String month, {String? dateFrom, String? dateTo}) async {
    // Preserve date range across internal reloads
    if (dateFrom != null) _lastDateFrom = dateFrom;
    if (dateTo != null) _lastDateTo = dateTo;
    final effectiveDateFrom = dateFrom ?? _lastDateFrom;
    final effectiveDateTo = dateTo ?? _lastDateTo;

    state = state.copyWith(isLoading: true, error: null, month: month);
    try {
      final result = await _repo.getSummary(month,
          dateFrom: effectiveDateFrom, dateTo: effectiveDateTo);

      // Fetch balance for the viewed month's date range
      int balance = 0;
      int income = 0;
      if (effectiveDateFrom != null && effectiveDateTo != null) {
        try {
          final monthlyRes = await _api.get('/summaries/monthly', queryParams: {
            'd_from_override': effectiveDateFrom,
            'd_to_override': effectiveDateTo,
          });
          balance = monthlyRes.data['balance'] as int? ?? 0;
          income = monthlyRes.data['total_income'] as int? ?? 0;
        } catch (_) {
          balance = 0;
        }
      }

      state = BudgetState(
        items: result.items,
        uncategorizedExpenses: result.uncategorizedExpenses,
        month: month,
        viewBalance: balance,
        totalIncome: income,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<bool> setBudget(int categoryId, int amount, String month, {int? cycleOn}) async {
    try {
      await _repo.create({
        'month': month,
        'category_id': categoryId,
        'amount': amount,
        if (cycleOn != null) 'cycle_on': cycleOn,
      });
      await load(month);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<bool> deleteBudget(int id) async {
    try {
      await _repo.delete(id);
      await load(state.month);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }
}

final budgetProvider = StateNotifierProvider<BudgetNotifier, BudgetState>((ref) {
  final api = ref.watch(apiClientProvider);
  return BudgetNotifier(BudgetRepository(api), api);
});
