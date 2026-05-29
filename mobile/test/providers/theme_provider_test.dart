import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/providers/theme_provider.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import '../helpers/mocks.dart';

class _MockSecureStorageForTheme extends SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> saveSecure(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<String?> getSecure(String key) async => _store[key];
}

void main() {
  group('ThemeModeNotifier', () {
    late _MockSecureStorageForTheme storage;
    late ThemeModeNotifier notifier;

    setUp(() {
      storage = _MockSecureStorageForTheme();
      notifier = ThemeModeNotifier(storage);
    });

    test('initial state is ThemeMode.system', () {
      expect(notifier.state, ThemeMode.system);
    });

    test('label returns System for initial state', () {
      expect(notifier.label, 'System');
    });

    test('setTheme changes to light mode and persists', () async {
      await notifier.setTheme(ThemeMode.light);
      expect(notifier.state, ThemeMode.light);
      expect(notifier.label, 'Light');
      final saved = await storage.getSecure('theme_mode');
      expect(saved, 'light');
    });

    test('setTheme changes to dark mode and persists', () async {
      await notifier.setTheme(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);
      expect(notifier.label, 'Dark');
      final saved = await storage.getSecure('theme_mode');
      expect(saved, 'dark');
    });

    test('setTheme changes to system mode and persists', () async {
      await notifier.setTheme(ThemeMode.light);
      // Now switch back to system
      await notifier.setTheme(ThemeMode.system);
      expect(notifier.state, ThemeMode.system);
      expect(notifier.label, 'System');
      final saved = await storage.getSecure('theme_mode');
      expect(saved, 'system');
    });

    test('loads persisted light theme from storage', () async {
      await storage.saveSecure('theme_mode', 'light');
      // Create new notifier that will load from storage
      final loadedNotifier = ThemeModeNotifier(storage);
      // Wait for async load
      await Future(() {});
      expect(loadedNotifier.state, ThemeMode.light);
    });

    test('loads persisted dark theme from storage', () async {
      await storage.saveSecure('theme_mode', 'dark');
      final loadedNotifier = ThemeModeNotifier(storage);
      await Future(() {});
      expect(loadedNotifier.state, ThemeMode.dark);
    });

    test('loads system theme when storage is empty', () async {
      final loadedNotifier = ThemeModeNotifier(storage);
      await Future(() {});
      expect(loadedNotifier.state, ThemeMode.system);
    });

    test('loads system theme for unknown value', () async {
      await storage.saveSecure('theme_mode', 'unknown');
      final loadedNotifier = ThemeModeNotifier(storage);
      await Future(() {});
      expect(loadedNotifier.state, ThemeMode.system);
    });

    test('label cycles correctly', () async {
      expect(notifier.label, 'System');
      await notifier.setTheme(ThemeMode.light);
      expect(notifier.label, 'Light');
      await notifier.setTheme(ThemeMode.dark);
      expect(notifier.label, 'Dark');
      await notifier.setTheme(ThemeMode.system);
      expect(notifier.label, 'System');
    });
  });
}
