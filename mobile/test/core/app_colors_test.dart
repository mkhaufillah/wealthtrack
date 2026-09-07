import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

void main() {
  group('AppColors Pastel cozy', () {
    test('light tokens match locked palette', () {
      AppColors.sync(Brightness.light);
      expect(AppColors.background, const Color(0xFFFFF3EE));
      expect(AppColors.surface, const Color(0xFFFFFFFF));
      expect(AppColors.textPrimary, const Color(0xFF4A3A48));
      expect(AppColors.accent, const Color(0xFFF3A6B8));
      expect(AppColors.highlight, const Color(0xFFE08B7C));
      expect(AppColors.success, const Color(0xFF4EAE90));
      expect(AppColors.heroFill, const Color(0xFFFFE8DC));
      expect(AppColors.heroOn, const Color(0xFF4A3A48));
    });

    test('dark tokens are plum not navy', () {
      AppColors.sync(Brightness.dark);
      expect(AppColors.background, const Color(0xFF2A2430));
      expect(AppColors.accent, const Color(0xFFE9A0B2));
      expect(AppColors.primary, isNot(const Color(0xFF58A6FF)));
      AppColors.sync(Brightness.light);
    });

    test('light avatar stays readable', () {
      AppColors.sync(Brightness.light);
      final bg = AppColors.avatarBackground('Filla');
      expect(bg.opacity, greaterThan(0.3));
      expect(AppColors.avatarText('Filla'), const Color(0xFF4A3A48));
    });
  });
}
