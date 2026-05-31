import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';

final ocrPendingCountProvider = StateNotifierProvider<OcrPendingCountNotifier, int>((ref) {
  return OcrPendingCountNotifier(ref.read(apiClientProvider));
});

class OcrPendingCountNotifier extends StateNotifier<int> {
  final ApiClient _api;
  OcrPendingCountNotifier(this._api) : super(0);

  Future<void> load() async {
    try {
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      state = data['count'] as int? ?? 0;
    } catch (_) {
      state = 0;
    }
  }
}
