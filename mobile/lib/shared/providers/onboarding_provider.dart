import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';
import 'app_providers.dart';

const kOnboardingDoneKey = 'onboarding_done';

/// `null` while loading, then whether first-run onboarding is finished.
final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, bool?>((ref) {
  return OnboardingNotifier(ref.watch(secureStorageProvider));
});

class OnboardingNotifier extends StateNotifier<bool?> {
  OnboardingNotifier(this._storage) : super(null) {
    _load();
  }

  final SecureStorage _storage;

  Future<void> _load() async {
    final v = await _storage.getSecure(kOnboardingDoneKey);
    state = v == '1';
  }

  Future<void> complete() async {
    await _storage.saveSecure(kOnboardingDoneKey, '1');
    state = true;
  }
}
