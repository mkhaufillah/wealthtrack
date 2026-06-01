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
  String? _dismissedFingerprint;

  OcrPendingCountNotifier(this._api) : super(const OcrState());

  Future<void> load() async {
    try {
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      final error = data['error'] as String?;
      final hasFailure = data['has_failure'] as bool? ?? false;

      // If this same error was dismissed, suppress it
      final showFailure = hasFailure && error != _dismissedFingerprint;

      // New error → reset dismissal so user sees it
      if (error != _dismissedFingerprint) {
        _dismissedFingerprint = null;
      }

      state = OcrState(
        pendingCount: data['count'] as int? ?? 0,
        error: showFailure ? error : null,
        hasFailure: showFailure,
      );
    } catch (_) {
      state = const OcrState();
    }
  }

  /// Dismiss the current OCR error banner (sticky for this error text)
  void dismissError() {
    if (state.hasFailure) {
      _dismissedFingerprint = state.error;
      state = OcrState(pendingCount: state.pendingCount);
    }
  }
}
