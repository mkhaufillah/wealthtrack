import 'package:flutter/material.dart';

class AppColors {
  // ─── Light palette ───────────────────────────────────
  static const Color _background = Color(0xFFF5F6FA);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _textPrimary = Color(0xFF1A1A2E);
  static const Color _textSecondary = Color(0xFF7F8C8D);
  static const Color _divider = Color(0xFFE8E8E8);

  // ─── Dark palette ────────────────────────────────────
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF161B22);
  static const Color darkCard = Color(0xFF1C2333);
  static const Color darkTextPrimary = Color(0xFFE6EDF3);
  static const Color darkTextSecondary = Color(0xFF8B949E);
  static const Color darkDivider = Color(0xFF30363D);
  static const Color darkPrimary = Color(0xFF58A6FF);

  // ─── Shared (theme-independent) ──────────────────────
  static const Color primary = Color(0xFF1A1A2E);
  static const Color secondary = Color(0xFF16213E);
  static const Color accent = Color(0xFF0F3460);
  static const Color highlight = Color(0xFFE94560);
  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFF39C12);

  // ─── Brightness-aware getters ────────────────────────
  static Brightness _brightness = Brightness.light;

  static void sync(Brightness b) => _brightness = b;

  static Color get background =>
      _brightness == Brightness.dark ? darkBackground : _background;
  static Color get surface =>
      _brightness == Brightness.dark ? darkSurface : _surface;
  static Color get textPrimary =>
      _brightness == Brightness.dark ? darkTextPrimary : _textPrimary;
  static Color get textSecondary =>
      _brightness == Brightness.dark ? darkTextSecondary : _textSecondary;
  static Color get divider =>
      _brightness == Brightness.dark ? darkDivider : _divider;
}

class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors._background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors._surface,
          error: AppColors.highlight,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors._textPrimary,
        ),
        cardColor: AppColors._surface,
        dividerColor: AppColors._divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors._background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors._divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors._divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors._surface,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors._textSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors._surface,
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkPrimary,
          secondary: AppColors.accent,
          surface: AppColors.darkSurface,
          error: AppColors.highlight,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.darkTextPrimary,
        ),
        cardColor: AppColors.darkSurface,
        dividerColor: AppColors.darkDivider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBackground,
          foregroundColor: AppColors.darkTextPrimary,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          labelStyle: TextStyle(color: AppColors.darkTextSecondary),
          hintStyle: TextStyle(color: AppColors.darkTextSecondary.withOpacity(0.6)),
          floatingLabelStyle: TextStyle(color: AppColors.darkPrimary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.darkDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.darkDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.darkPrimary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.darkTextPrimary,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.darkTextSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkSurface,
        ),
      );
}
