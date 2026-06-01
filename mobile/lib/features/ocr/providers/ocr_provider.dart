import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/providers/app_providers.dart';

class OcrState {
  final int pendingCount;
  final String? error;
  final bool hasFailure;
  final int? failedJobId;

  const OcrState({
    this.pendingCount = 0,
    this.error,
    this.hasFailure = false,
    this.failedJobId,
  });
}

final ocrPendingCountProvider = StateNotifierProvider<OcrPendingCountNotifier, OcrState>((ref) {
  return OcrPendingCountNotifier(
    ref.read(apiClientProvider),
    ref.read(secureStorageProvider),
  );
});

class OcrPendingCountNotifier extends StateNotifier<OcrState> {
  final ApiClient _api;
  final SecureStorage _storage;
  int? _dismissedJobId;
  bool _initialized = false;

  OcrPendingCountNotifier(this._api, this._storage) : super(const OcrState());

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _initialized = true;
      final stored = await _storage.getSecure('ocr_dismissed_job_id');
      if (stored != null && stored.isNotEmpty) {
        _dismissedJobId = int.tryParse(stored);
      }
    }
  }

  Future<void> load() async {
    try {
      await _ensureInitialized();
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      final hasFailure = data['has_failure'] as bool? ?? false;
      final error = data['error'] as String?;
      final failedJobId = data['failed_job_id'] as int?;

      // Show failure only if it's a different job than the dismissed one.
      // Each OCR job has a unique ID, so this naturally differentiates
      // old vs new failures even when the error text is identical.
      final showFailure = hasFailure && failedJobId != _dismissedJobId;

      state = OcrState(
        pendingCount: data['count'] as int? ?? 0,
        error: showFailure ? error : null,
        hasFailure: showFailure,
        failedJobId: failedJobId,
      );
    } catch (_) {
      state = const OcrState();
    }
  }

  /// Dismiss the current OCR error banner — suppressed by failed_job_id.
  Future<void> dismissError() async {
    if (state.hasFailure && state.failedJobId != null) {
      _dismissedJobId = state.failedJobId;
      await _storage.saveSecure('ocr_dismissed_job_id', state.failedJobId.toString());
      state = OcrState(pendingCount: state.pendingCount);
    }
  }

  /// Clear visible error state without resetting dismissed fingerprint.
  /// Use when user starts a new OCR scan — old error banner disappears
  /// immediately, but new failures (different job_id) still show.
  void clearError() {
    if (state.hasFailure) {
      state = OcrState(pendingCount: state.pendingCount);
    }
  }
}
