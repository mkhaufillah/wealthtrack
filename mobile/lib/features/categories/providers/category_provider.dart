import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';

class CategoryManagementState {
  final bool isLoading;
  final List<Map<String, dynamic>> categories;
  final String? error;

  const CategoryManagementState({
    this.isLoading = false,
    this.categories = const [],
    this.error,
  });

  CategoryManagementState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? categories,
    String? error,
  }) => CategoryManagementState(
    isLoading: isLoading ?? this.isLoading,
    categories: categories ?? this.categories,
    error: error,
  );
}

class CategoryManagementNotifier extends StateNotifier<CategoryManagementState> {
  final ApiClient _api;
  CategoryManagementNotifier(this._api) : super(const CategoryManagementState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _api.get('/categories');
      state = CategoryManagementState(
        isLoading: false,
        categories: List<Map<String, dynamic>>.from(res.data),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try {
      await _api.post('/categories', data: data);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> update(int id, Map<String, dynamic> data) async {
    try {
      await _api.put('/categories/$id', data: data);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final categoryManagementProvider =
    StateNotifierProvider<CategoryManagementNotifier, CategoryManagementState>((ref) {
  return CategoryManagementNotifier(ref.read(apiClientProvider));
});
