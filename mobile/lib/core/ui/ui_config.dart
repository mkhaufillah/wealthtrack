import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import '../theme/app_theme.dart';
import 'copy_fallback.dart';
import 'money.dart';
import '../../shared/providers/app_providers.dart';

const _cacheKey = 'ui_bootstrap';

class UiConfigNotifier extends StateNotifier<Map<String, dynamic>> {
  UiConfigNotifier(this._api, this._storage) : super(const {});

  final ApiClient _api;
  final SecureStorage _storage;

  Future<void> load() async {
    final cached = await _storage.getSecure(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        applyMap(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    try {
      final res = await _api.get('/ui/bootstrap');
      final data = res.data;
      if (data is Map<String, dynamic> && data['copy'] is Map) {
        await _storage.saveSecure(_cacheKey, jsonEncode(data));
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
