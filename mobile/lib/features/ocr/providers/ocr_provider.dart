import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
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
  return OcrPendingCountNotifier(
    ref.read(apiClientProvider),
    ref.read(secureStorageProvider),
  );
});

class OcrPendingCountNotifier extends StateNotifier<OcrState> {
  final ApiClient _api;
  final SecureStorage _storage;
  String? _dismissedFingerprint;
  bool _initialized = false;

  OcrPendingCountNotifier(this._api, this._storage) : super(const OcrState());

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _initialized = true;
      _dismissedFingerprint = await _storage.getSecure('ocr_dismissed_error');
    }
  }

  Future<void> load() async {
    try {
      await _ensureInitialized();
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      final error = data['error'] as String?;
      final hasFailure = data['has_failure'] as bool? ?? false;

      // If this same error was dismissed, suppress it
      final showFailure = hasFailure && error != _dismissedFingerprint;

      // New error (different text or null vs non-null) → reset dismissal
      if (error != _dismissedFingerprint) {
        _dismissedFingerprint = null;
        await _storage.saveSecure('ocr_dismissed_error', '');
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
  Future<void> dismissError() async {
    if (state.hasFailure && state.error != null) {
      _dismissedFingerprint = state.error;
      await _storage.saveSecure('ocr_dismissed_error', state.error!);
      state = OcrState(pendingCount: state.pendingCount);
    }
  }

  /// Clear dismissed fingerprint so a new OCR attempt shows errors again.
  Future<void> resetDismissed() async {
    _dismissedFingerprint = null;
    await _storage.saveSecure('ocr_dismissed_error', '');
  }
}
