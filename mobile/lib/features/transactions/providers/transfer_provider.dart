import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/transaction_repository.dart';

class TransferBalanceState {
  final bool isSubmitting;
  final String? error;
  final bool success;
  final int transactionCount;

  const TransferBalanceState({
    this.isSubmitting = false,
    this.error,
    this.success = false,
    this.transactionCount = 0,
  });

  TransferBalanceState copyWith({
    bool? isSubmitting,
    String? error,
    bool? success,
    int? transactionCount,
  }) =>
      TransferBalanceState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: error ?? this.error,
        success: success ?? this.success,
        transactionCount: transactionCount ?? this.transactionCount,
      );
}

class TransferBalanceNotifier extends StateNotifier<TransferBalanceState> {
  final TransactionRepository _repo;
  final ApiClient _api;

  TransferBalanceNotifier(this._repo, this._api)
      : super(const TransferBalanceState());

  /// Fetch household members for the transfer picker.
  Future<List<Map<String, dynamic>>> getHouseholdMembers() async {
    try {
      final res = await _api.get('/households/me');
      final members = (res.data['members'] as List).cast<Map<String, dynamic>>();
      return members;
    } catch (e) {
      return [];
    }
  }

  Future<bool> submit({
    required String date,
    required List<Map<String, dynamic>> transfers,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null, success: false);
    try {
      final result = await _repo.transferBalance(
        date: date,
        transfers: transfers,
      );
      final transactions = (result['transactions'] as List);
      state = state.copyWith(
        isSubmitting: false,
        success: true,
        transactionCount: transactions.length,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: e.toString(),
      );
      return false;
    }
  }

  void reset() {
    state = const TransferBalanceState();
  }
}

final transferBalanceProvider =
    StateNotifierProvider<TransferBalanceNotifier, TransferBalanceState>((ref) {
  final api = ref.watch(apiClientProvider);
  return TransferBalanceNotifier(TransactionRepository(api), api);
});
