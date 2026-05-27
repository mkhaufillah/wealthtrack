import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/transaction_repository.dart';
import '../models/transaction_model.dart';

class TransactionListState {
  final bool isLoading; final String? error;
  final List<TransactionModel> transactions; final int total;
  final bool isTransferring; final String? transferError;
  const TransactionListState({this.isLoading = false, this.error, this.transactions = const [], this.total = 0,
    this.isTransferring = false, this.transferError});
  TransactionListState copyWith({bool? isLoading, String? error, List<TransactionModel>? transactions, int? total,
    bool? isTransferring, String? transferError}) =>
    TransactionListState(isLoading: isLoading ?? this.isLoading, error: error ?? this.error,
        transactions: transactions ?? this.transactions, total: total ?? this.total,
        isTransferring: isTransferring ?? this.isTransferring,
        transferError: transferError ?? this.transferError);
}

class TransactionListNotifier extends StateNotifier<TransactionListState> {
  final TransactionRepository _repo;
  final ApiClient _api;
  TransactionListNotifier(this._repo, this._api) : super(const TransactionListState());

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

  Future<bool> update(int id, Map<String, dynamic> data) async {
    try { await _repo.update(id, data); await load(refresh: true); return true; }
    catch (e) { state = state.copyWith(error: e.toString()); return false; }
  }

  Future<bool> delete(int id) async {
    try { await _repo.delete(id); await load(refresh: true); return true; }
    catch (e) { state = state.copyWith(error: e.toString()); return false; }
  }

  Future<bool> transferOwner(int txnId, int userId) async {
    state = state.copyWith(isTransferring: true, transferError: null);
    try {
      await _repo.transferOwner(txnId, userId);
      await load(refresh: true);
      return true;
    } catch (e) {
      state = state.copyWith(isTransferring: false, transferError: e.toString());
      return false;
    }
  }

  /// Fetch household members for the current user.
  Future<List<Map<String, dynamic>>> getHouseholdMembers() async {
    try {
      final res = await _api.get('/households/me');
      final members = (res.data['members'] as List).cast<Map<String, dynamic>>();
      return members;
    } catch (e) {
      return [];
    }
  }
}

final transactionListProvider = StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return TransactionListNotifier(TransactionRepository(api), api);
});