import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/budget_repository.dart';
import '../models/budget_model.dart';

class BudgetSuggestionState {
  final bool isLoading;
  final String? error;
  final BudgetSuggestionResponse? response;
  final int numAccepted;
  final bool isApplying;

  const BudgetSuggestionState({
    this.isLoading = false,
    this.error,
    this.response,
    this.numAccepted = 0,
    this.isApplying = false,
  });

  BudgetSuggestionState copyWith({
    bool? isLoading,
    String? error,
    BudgetSuggestionResponse? response,
    int? numAccepted,
    bool? isApplying,
  }) =>
      BudgetSuggestionState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        response: response ?? this.response,
        numAccepted: numAccepted ?? this.numAccepted,
        isApplying: isApplying ?? this.isApplying,
      );
}

class BudgetSuggestionNotifier extends StateNotifier<BudgetSuggestionState> {
  final BudgetRepository _repo;
  final ApiClient _api;

  BudgetSuggestionNotifier(this._repo, this._api) : super(const BudgetSuggestionState());

  Future<void> load(String month, {int numCycles = 3}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _repo.getSuggestions(month, numCycles: numCycles);
      state = state.copyWith(isLoading: false, response: response, numAccepted: 0);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _api.handleError(e).toString());
    }
  }

  void toggleAccept(int categoryId) {
    final resp = state.response;
    if (resp == null) return;
    final updated = resp.items.map((item) {
      if (item.categoryId == categoryId) {
        return item.copyWith(accepted: !item.accepted);
      }
      return item;
    }).toList();
    final accepted = updated.where((i) => i.accepted).length;
    state = state.copyWith(
      response: BudgetSuggestionResponse(
          updated, resp.totalSuggested, resp.totalIncome, resp.warning),
      numAccepted: accepted,
    );
  }

  void toggleSelectAll(bool selectAll) {
    final resp = state.response;
    if (resp == null) return;
    final updated = resp.items.map((item) {
      if (!item.hasBudget) {
        return item.copyWith(accepted: selectAll);
      }
      return item;
    }).toList();
    final accepted = updated.where((i) => i.accepted).length;
    state = state.copyWith(
      response: BudgetSuggestionResponse(
          updated, resp.totalSuggested, resp.totalIncome, resp.warning),
      numAccepted: accepted,
    );
  }

  Future<bool> applySelected(String month) async {
    final resp = state.response;
    if (resp == null) return false;
    state = state.copyWith(isApplying: true);
    try {
      final selected = resp.items.where((i) => i.accepted && !i.hasBudget).toList();
      for (final item in selected) {
        await _repo.create({
          'month': month,
          'category_id': item.categoryId,
          'amount': item.suggestedAmount,
        });
      }
      // Mark applied items as accepted=false, hasBudget=true
      final appliedIds = selected.map((i) => i.categoryId).toSet();
      final updated = resp.items.map((item) {
        if (appliedIds.contains(item.categoryId)) {
          return item.copyWith(accepted: false, hasBudget: true);
        }
        return item;
      }).toList();
      state = state.copyWith(
        isApplying: false,
        response: BudgetSuggestionResponse(
            updated, resp.totalSuggested, resp.totalIncome, resp.warning),
        numAccepted: 0,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isApplying: false, error: _api.handleError(e).toString());
      return false;
    }
  }
}

final budgetSuggestionProvider =
    StateNotifierProvider<BudgetSuggestionNotifier, BudgetSuggestionState>((ref) {
  final api = ref.watch(apiClientProvider);
  return BudgetSuggestionNotifier(BudgetRepository(api), api);
});
