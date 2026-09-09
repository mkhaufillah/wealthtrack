import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/ui/ui_config.dart';
import 'app_providers.dart';

const kUiLocaleKey = 'ui_locale';
const kDefaultLocale = 'id-ID';

final localeProvider = StateNotifierProvider<LocaleNotifier, String>((ref) {
  return LocaleNotifier(
    ref.watch(secureStorageProvider),
    ref.read(uiConfigProvider.notifier),
  );
});

class LocaleNotifier extends StateNotifier<String> {
  LocaleNotifier(this._storage, this._ui) : super(kDefaultLocale) {
    _load();
  }

  final SecureStorage _storage;
  final UiConfigNotifier _ui;

  Future<void> _load() async {
    final saved = await _storage.getSecure(kUiLocaleKey);
    if (saved == 'en-US' || saved == 'id-ID') {
      state = saved!;
      _ui.applyLocale(saved);
    }
  }

  Locale get materialLocale =>
      state == 'en-US' ? const Locale('en') : const Locale('id');

  Future<void> setLocale(String locale) async {
    final next = locale == 'en-US' || locale == 'en' ? 'en-US' : 'id-ID';
    _ui.applyLocale(next);
    if (state != next) state = next;
    await _storage.saveSecure(kUiLocaleKey, next);
    await _ui.load(locale: next);
  }
}
