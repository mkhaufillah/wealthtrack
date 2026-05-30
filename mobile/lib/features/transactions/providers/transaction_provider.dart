import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/transaction_repository.dart';
import '../models/transaction_model.dart';

class TransactionListState {
  final bool isLoading; final String? error;
  final List<TransactionModel> transactions; final int total;
  final bool isTransferring; final String? transferError;

  // Filters
  final String typeFilter; // 'all', 'expense', 'income'
  final List<int> selectedCategoryIds; // empty = all
  final String sortBy; // '-date', 'date', '-amount', 'amount', 'name', '-name'
  final String searchQuery;

  // Pagination
  final int page; final int perPage;
  int get totalPages => (total + perPage - 1) ~/ perPage;

  const TransactionListState({
    this.isLoading = false, this.error,
    this.transactions = const [], this.total = 0,
    this.isTransferring = false, this.transferError,
    this.typeFilter = 'all', this.selectedCategoryIds = const [],
    this.sortBy = '-date', this.searchQuery = '',
    this.page = 1, this.perPage = 10,
  });

  TransactionListState copyWith({
    bool? isLoading, String? error,
    List<TransactionModel>? transactions, int? total,
    bool? isTransferring, String? transferError,
    String? typeFilter, List<int>? selectedCategoryIds,
    String? sortBy, String? searchQuery,
    int? page, int? perPage,
  }) => TransactionListState(
    isLoading: isLoading ?? this.isLoading, error: error ?? this.error,
    transactions: transactions ?? this.transactions, total: total ?? this.total,
    isTransferring: isTransferring ?? this.isTransferring,
    transferError: transferError ?? this.transferError,
    typeFilter: typeFilter ?? this.typeFilter,
    selectedCategoryIds: selectedCategoryIds ?? this.selectedCategoryIds,
    sortBy: sortBy ?? this.sortBy, searchQuery: searchQuery ?? this.searchQuery,
    page: page ?? this.page, perPage: perPage ?? this.perPage,
  );
}

class TransactionListNotifier extends StateNotifier<TransactionListState> {
  final TransactionRepository _repo;
  final ApiClient _api;

  // Cached categories for filter UI
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => _categories;

  TransactionListNotifier(this._repo, this._api)
      : super(const TransactionListState()) {
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await _api.get('/categories');
      _categories = (res.data as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {}
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.list(
        page: state.page,
        perPage: state.perPage,
        sort: state.sortBy,
        type: state.typeFilter == 'all' ? null : state.typeFilter,
        categoryIds: state.selectedCategoryIds.isEmpty ? null : state.selectedCategoryIds,
        q: state.searchQuery.isEmpty ? null : state.searchQuery,
      );
      state = TransactionListState(
        transactions: result['transactions'] as List<TransactionModel>,
        total: result['total'] as int,
        typeFilter: state.typeFilter,
        selectedCategoryIds: state.selectedCategoryIds,
        sortBy: state.sortBy,
        searchQuery: state.searchQuery,
        page: state.page,
        perPage: state.perPage,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _api.handleError(e).toString());
    }
  }

  // -- Filter actions (each resets to page 1) --

  void setTypeFilter(String type) {
    if (state.typeFilter == type) return;
    state = state.copyWith(typeFilter: type, page: 1);
    load();
  }

  void setCategoryFilter(List<int> ids) {
    state = state.copyWith(selectedCategoryIds: ids, page: 1);
    load();
  }

  void setSortBy(String sort) {
    if (state.sortBy == sort) return;
    state = state.copyWith(sortBy: sort, page: 1);
    load();
  }

  void setSearchQuery(String q) {
    state = state.copyWith(searchQuery: q, page: 1);
    load();
  }

  // -- Pagination --

  void goToPage(int p) {
    if (p < 1 || p > state.totalPages || p == state.page) return;
    state = state.copyWith(page: p);
    load();
  }

  void nextPage() => goToPage(state.page + 1);
  void prevPage() => goToPage(state.page - 1);

  // -- Mutations (carry over filters) --

  Future<bool> create(Map<String, dynamic> data) async {
    try { await _repo.create(data); await load(); return true; }
    catch (e) { state = state.copyWith(error: _api.handleError(e).toString()); return false; }
  }

  Future<bool> update(int id, Map<String, dynamic> data) async {
    try { await _repo.update(id, data); await load(); return true; }
    catch (e) { state = state.copyWith(error: _api.handleError(e).toString()); return false; }
  }

  Future<bool> delete(int id) async {
    try { await _repo.delete(id); await load(); return true; }
    catch (e) { state = state.copyWith(error: _api.handleError(e).toString()); return false; }
  }

  Future<bool> transferOwner(int txnId, int userId) async {
    state = state.copyWith(isTransferring: true, transferError: null);
    try {
      await _repo.transferOwner(txnId, userId);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isTransferring: false, transferError: _api.handleError(e).toString());
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getHouseholdMembers() async {
    try {
      final res = await _api.get('/households/me');
      return (res.data['members'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
}

final transactionListProvider = StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return TransactionListNotifier(TransactionRepository(api), api);
});

/// Tracks whether the category filter bottom sheet is open.
/// MainShell watches this to hide the FAB when the sheet is open.
final isCategoryFilterSheetOpenProvider = StateProvider<bool>((ref) => false);
