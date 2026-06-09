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
  final ExtraPaymentPreview? extraPreview;
  final List<ExtraPaymentRecord> extraPayments;

  const KPRState({
    this.isLoading = false,
    this.error,
    this.simulations = const [],
    this.selectedSimulation,
    this.extraPreview,
    this.extraPayments = const [],
  });

  KPRState copyWith({
    bool? isLoading,
    String? error,
    List<KPRSimulation>? simulations,
    KPRSimulation? selectedSimulation,
    ExtraPaymentPreview? extraPreview,
    List<ExtraPaymentRecord>? extraPayments,
    bool clearError = false,
    bool clearSelection = false,
    bool clearExtraPreview = false,
  }) =>
      KPRState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        simulations: simulations ?? this.simulations,
        selectedSimulation:
            clearSelection ? null : (selectedSimulation ?? this.selectedSimulation),
        extraPreview: clearExtraPreview
            ? null
            : (extraPreview ?? this.extraPreview),
        extraPayments: extraPayments ?? this.extraPayments,
      );
}

class KPRNotifier extends StateNotifier<KPRState> {
  final ApiClient _api;
  final Ref _ref;

  KPRNotifier(this._api, this._ref) : super(const KPRState());

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
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
    state = state.copyWith(isLoading: true, clearError: true);
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
        clearSelection: state.selectedSimulation?.id == id,
        clearError: true,
      );
      _ref.read(homeRefreshProvider.notifier).state++;
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  // ── Extra Payment: Preview ──────────────────────────────────────

  Future<ExtraPaymentPreview?> previewExtraPayment({
    required int simId,
    required int amount,
    double penaltyRate = 0,
    required int applyMonth,
  }) async {
    state = state.copyWith(isLoading: true, clearExtraPreview: true);
    try {
      final res = await _api.post(
        '/kpr/simulations/$simId/extra-payments/preview',
        data: {
          'amount': amount,
          'penalty_rate': penaltyRate,
          'apply_month': applyMonth,
        },
      );
      final preview = ExtraPaymentPreview.fromJson(
          res.data as Map<String, dynamic>);
      state = state.copyWith(isLoading: false, extraPreview: preview);
      return preview;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _api.handleError(e).toString());
      return null;
    }
  }

  // ── Extra Payment: Commit ───────────────────────────────────────

  Future<bool> createExtraPayment({
    required int simId,
    required int amount,
    double penaltyRate = 0,
    required int applyMonth,
    required String reductionType,
  }) async {
    try {
      await _api.post(
        '/kpr/simulations/$simId/extra-payments',
        data: {
          'amount': amount,
          'penalty_rate': penaltyRate,
          'apply_month': applyMonth,
          'reduction_type': reductionType,
        },
      );
      // Refresh detail to get updated schedule
      await loadDetail(simId);
      // Refresh extra payments list
      await loadExtraPayments(simId);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  // ── Extra Payment: List ─────────────────────────────────────────

  Future<void> loadExtraPayments(int simId) async {
    try {
      final res = await _api.get(
        '/kpr/simulations/$simId/extra-payments',
      );
      final data = res.data;
      final list = (data as List)
          .map((e) =>
              ExtraPaymentRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(extraPayments: list);
    } catch (e) {
      state = state.copyWith(
          error: _api.handleError(e).toString());
    }
  }

  // ── Extra Payment: Delete ───────────────────────────────────────

  Future<bool> deleteExtraPayment(int simId, int extraPaymentId) async {
    try {
      await _api.delete(
          '/kpr/simulations/$simId/extra-payments/$extraPaymentId');
      // Refresh detail to get restored schedule
      await loadDetail(simId);
      await loadExtraPayments(simId);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }
}

final kprProvider =
    StateNotifierProvider<KPRNotifier, KPRState>((ref) {
  final api = ref.watch(apiClientProvider);
  return KPRNotifier(api, ref);
});
