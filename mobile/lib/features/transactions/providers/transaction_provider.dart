import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/transaction_repository.dart';
import '../models/transaction_model.dart';

class TransactionListState {
  final bool isLoading; final String? error;
  final List<TransactionModel> transactions; final int total;
  const TransactionListState({this.isLoading = false, this.error, this.transactions = const [], this.total = 0});
  TransactionListState copyWith({bool? isLoading, String? error, List<TransactionModel>? transactions, int? total}) =>
      TransactionListState(isLoading: isLoading ?? this.isLoading, error: error,
        transactions: transactions ?? this.transactions, total: total ?? this.total);
}

class TransactionListNotifier extends StateNotifier<TransactionListState> {
  final TransactionRepository _repo;
  TransactionListNotifier(this._repo) : super(const TransactionListState());

  Future<void> load({bool refresh = false}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.list();
      state = TransactionListState(transactions: result['transactions'] as List<TransactionModel>, total: result['total'] as int);
    } catch (e) { state = state.copyWith(isLoading: false, error: e.toString()); }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try { await _repo.create(data); await load(refresh: true); return true; }
    catch (e) { state = state.copyWith(error: e.toString()); return false; }
  }

  Future<bool> delete(int id) async {
    try { await _repo.delete(id); await load(refresh: true); return true; }
    catch (e) { state = state.copyWith(error: e.toString()); return false; }
  }
}

final transactionListProvider = StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return TransactionListNotifier(TransactionRepository(api));
});