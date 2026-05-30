import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../transactions/models/transaction_model.dart';

class DashboardState {
  final bool isLoading; final String? error;
  final int totalIncome; final int totalExpense; final int balance;
  final List<TransactionModel> recentTransactions; final int totalTransactions;
  const DashboardState({this.isLoading = false, this.error, this.totalIncome = 0, this.totalExpense = 0,
    this.balance = 0, this.recentTransactions = const [], this.totalTransactions = 0});

  DashboardState copyWith({bool? isLoading, String? error, int? totalIncome, int? totalExpense,
    int? balance, List<TransactionModel>? recentTransactions, int? totalTransactions}) =>
    DashboardState(isLoading: isLoading ?? this.isLoading, error: error ?? this.error,
      totalIncome: totalIncome ?? this.totalIncome, totalExpense: totalExpense ?? this.totalExpense,
      balance: balance ?? this.balance, recentTransactions: recentTransactions ?? this.recentTransactions,
      totalTransactions: totalTransactions ?? this.totalTransactions);
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final ApiClient _api;
  DashboardNotifier(this._api) : super(const DashboardState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final summaryRes = await _api.get('/summaries/current-month', queryParams: {'use_cycle': 'true'});
      final summary = summaryRes.data;
      final txnRes = await _api.get('/transactions', queryParams: {'per_page': 5, 'sort': '-date'});
      final txns = (txnRes.data['data'] as List)
          .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = DashboardState(
        totalIncome: summary['total_income'] ?? 0, totalExpense: summary['total_expense'] ?? 0,
        balance: summary['balance'] ?? 0, recentTransactions: txns,
        totalTransactions: txnRes.data['meta']['total'] ?? 0,
      );
    } catch (e) { state = state.copyWith(isLoading: false, error: _api.handleError(e).toString()); }
  }
}

final dashboardProvider = StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final api = ref.watch(apiClientProvider);
  return DashboardNotifier(api);
});

/// Increment this counter to signal home screen to refresh dashboard data.
final homeRefreshProvider = StateProvider<int>((ref) => 0);