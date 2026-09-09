import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import '../theme/app_theme.dart';
import 'copy_fallback.dart';
import 'money.dart';
import '../../shared/providers/app_providers.dart';

class UiConfigNotifier extends StateNotifier<Map<String, dynamic>> {
  UiConfigNotifier(this._api, this._storage) : super(const {});

  final ApiClient _api;
  final SecureStorage _storage;
  final Map<String, Map<String, dynamic>> _bootByLocale = {};
  int _gen = 0;

  String _norm(String? locale) {
    if (locale == 'en-US' || locale == 'en') return 'en-US';
    return 'id-ID';
  }

  String _cacheKey(String loc) => 'ui_bootstrap_$loc';

  /// Instant: in-memory boot or offline fallback. No await.
  void applyLocale(String locale) {
    final loc = _norm(locale);
    activeUiLocale = loc;
    final boot = _bootByLocale[loc];
    if (boot != null) {
      applyMap(boot);
      return;
    }
    applyRemoteCopy(loc == 'en-US' ? copyFallbackEn : copyFallback);
    state = {...state, 'locale': loc};
  }

  Future<void> load({String? locale}) async {
    final loc = _norm(
      locale ?? await _storage.getSecure('ui_locale') ?? 'id-ID',
    );
    final gen = ++_gen;
    applyLocale(loc);

    final cached = await _storage.getSecure(_cacheKey(loc));
    if (gen != _gen) return;
    if (cached != null && cached.isNotEmpty) {
      try {
        final data = jsonDecode(cached);
        if (data is Map<String, dynamic> &&
            data['copy'] is Map &&
            (data['locale'] == loc || data['locale'] == null)) {
          data['locale'] = loc;
          _bootByLocale[loc] = data;
          applyMap(data);
        }
      } catch (_) {}
    }
    if (gen != _gen) return;

    try {
      final res = await _api.get('/ui/bootstrap', queryParams: {'locale': loc});
      if (gen != _gen) return;
      final data = res.data;
      if (data is Map<String, dynamic> && data['copy'] is Map) {
        data['locale'] = loc;
        _bootByLocale[loc] = data;
        await _storage.saveSecure(_cacheKey(loc), jsonEncode(data));
        if (gen != _gen) return;
        applyMap(data);
      }
    } catch (_) {}
  }

  void applyMap(Map<String, dynamic> data) {
    final copyRaw = data['copy'];
    if (copyRaw is Map) {
      applyRemoteCopy({
        for (final e in copyRaw.entries) e.key.toString(): e.value.toString(),
      });
    }
    final format = data['format'];
    if (format is Map) {
      MoneyFormat.apply(Map<String, dynamic>.from(format));
    }
    final theme = data['theme'];
    if (theme is Map) {
      AppColors.applyRemote(
        light: theme['light'] is Map
            ? Map<String, dynamic>.from(theme['light'] as Map)
            : null,
        dark: theme['dark'] is Map
            ? Map<String, dynamic>.from(theme['dark'] as Map)
            : null,
      );
    }
    state = Map<String, dynamic>.from(data);
  }
}

final uiConfigProvider =
    StateNotifierProvider<UiConfigNotifier, Map<String, dynamic>>((ref) {
  return UiConfigNotifier(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});
