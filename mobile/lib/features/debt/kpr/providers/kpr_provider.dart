import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../home/providers/dashboard_provider.dart';
import '../../models/kpr_model.dart';

class KPRState {
  final bool isLoading;
  final String? error;
  final List<KPRSimulation> simulations;
  final KPRSimulation? selectedSimulation;

  const KPRState({
    this.isLoading = false,
    this.error,
    this.simulations = const [],
    this.selectedSimulation,
  });

  KPRState copyWith({
    bool? isLoading,
    String? error,
    List<KPRSimulation>? simulations,
    KPRSimulation? selectedSimulation,
  }) =>
      KPRState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        simulations: simulations ?? this.simulations,
        selectedSimulation: selectedSimulation ?? this.selectedSimulation,
      );
}

class KPRNotifier extends StateNotifier<KPRState> {
  final ApiClient _api;
  final Ref _ref;

  KPRNotifier(this._api, this._ref) : super(const KPRState());

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _api.get('/kpr/simulations');
      final data = res.data;
      final list = (data as List)
          .map((e) => KPRSimulation.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(isLoading: false, simulations: list);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<void> loadDetail(int id) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _api.get('/kpr/simulations/$id');
      final sim =
          KPRSimulation.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(
          isLoading: false, selectedSimulation: sim);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/kpr/simulations', data: data);
      final sim =
          KPRSimulation.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(
        selectedSimulation: sim,
        simulations: [...state.simulations, sim],
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      await _api.delete('/kpr/simulations/$id');
      state = state.copyWith(
        simulations:
            state.simulations.where((s) => s.id != id).toList(),
        selectedSimulation: state.selectedSimulation?.id == id
            ? null
            : state.selectedSimulation,
      );
      _ref.read(homeRefreshProvider.notifier).state++;
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void clearSelection() {
    state = state.copyWith(selectedSimulation: null);
  }
}

final kprProvider =
    StateNotifierProvider<KPRNotifier, KPRState>((ref) {
  final api = ref.watch(apiClientProvider);
  return KPRNotifier(api, ref);
});
