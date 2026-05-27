import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/budget_repository.dart';
import '../models/budget_model.dart';

class BudgetState {
  final bool isLoading;
  final String? error;
  final List<BudgetSummaryItem> items;
  final String month;

  const BudgetState({
    this.isLoading = false,
    this.error,
    this.items = const [],
    this.month = '',
  });

  BudgetState copyWith({
    bool? isLoading,
    String? error,
    List<BudgetSummaryItem>? items,
    String? month,
  }) =>
      BudgetState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        items: items ?? this.items,
        month: month ?? this.month,
      );
}

class BudgetNotifier extends StateNotifier<BudgetState> {
  final BudgetRepository _repo;

  BudgetNotifier(this._repo) : super(const BudgetState());

  Future<void> load(String month) async {
    state = state.copyWith(isLoading: true, error: null, month: month);
    try {
      final items = await _repo.getSummary(month);
      state = BudgetState(items: items, month: month);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> setBudget(int categoryId, int amount, String month) async {
    try {
      await _repo.create({
        'month': month,
        'category_id': categoryId,
        'amount': amount,
      });
      await load(month);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteBudget(int id) async {
    try {
      await _repo.delete(id);
      await load(state.month);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final budgetProvider = StateNotifierProvider<BudgetNotifier, BudgetState>((ref) {
  final api = ref.watch(apiClientProvider);
  return BudgetNotifier(BudgetRepository(api));
});
