import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';

class DashboardState {
  final bool isLoading; final String? error;
  final int totalIncome; final int totalExpense; final int balance;
  final List<Map<String, dynamic>> recentTransactions; final int totalTransactions;
  const DashboardState({this.isLoading = false, this.error, this.totalIncome = 0, this.totalExpense = 0,
    this.balance = 0, this.recentTransactions = const [], this.totalTransactions = 0});

  DashboardState copyWith({bool? isLoading, String? error, int? totalIncome, int? totalExpense,
    int? balance, List<Map<String, dynamic>>? recentTransactions, int? totalTransactions}) =>
    DashboardState(isLoading: isLoading ?? this.isLoading, error: error,
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
      final summaryRes = await _api.get('/summaries/current-month');
      final summary = summaryRes.data;
      final txnRes = await _api.get('/transactions', queryParams: {'per_page': 5, 'sort': '-date'});
      final txns = List<Map<String, dynamic>>.from(txnRes.data['data']);
      state = DashboardState(
        totalIncome: summary['total_income'] ?? 0, totalExpense: summary['total_expense'] ?? 0,
        balance: summary['balance'] ?? 0, recentTransactions: txns,
        totalTransactions: txnRes.data['meta']['total'] ?? 0,
      );
    } catch (e) { state = state.copyWith(isLoading: false, error: e.toString()); }
  }
}

final dashboardProvider = StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final api = ref.watch(apiClientProvider);
  return DashboardNotifier(api);
});

/// Increment this counter to signal home screen to refresh dashboard data.
final homeRefreshProvider = StateProvider<int>((ref) => 0);