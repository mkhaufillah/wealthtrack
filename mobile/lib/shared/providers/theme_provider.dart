import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';

/// Persisted theme preference: 'system', 'light', or 'dark'.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(secureStorageProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SecureStorage _storage;
  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final saved = await _storage.getSecure('theme_mode');
    if (saved == 'light') {
      state = ThemeMode.light;
    } else if (saved == 'dark') {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.system;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final val = mode == ThemeMode.system ? 'system'
              : mode == ThemeMode.light ? 'light'
              : 'dark';
    await _storage.saveSecure('theme_mode', val);
  }

  String get label {
    switch (state) {
      case ThemeMode.system: return 'System';
      case ThemeMode.light: return 'Light';
      case ThemeMode.dark: return 'Dark';
    }
  }
}
