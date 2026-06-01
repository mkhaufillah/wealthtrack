import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';

class OcrState {
  final int pendingCount;
  final String? error;
  final bool hasFailure;

  const OcrState({
    this.pendingCount = 0,
    this.error,
    this.hasFailure = false,
  });
}

final ocrPendingCountProvider = StateNotifierProvider<OcrPendingCountNotifier, OcrState>((ref) {
  return OcrPendingCountNotifier(ref.read(apiClientProvider));
});

class OcrPendingCountNotifier extends StateNotifier<OcrState> {
  final ApiClient _api;
  OcrPendingCountNotifier(this._api) : super(const OcrState());

  Future<void> load() async {
    try {
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      state = OcrState(
        pendingCount: data['count'] as int? ?? 0,
        error: data['error'] as String?,
        hasFailure: data['has_failure'] as bool? ?? false,
      );
    } catch (_) {
      state = const OcrState();
    }
  }

  /// Dismiss the current OCR error banner
  void dismissError() {
    if (state.hasFailure) {
      state = OcrState(pendingCount: state.pendingCount);
    }
  }
}
