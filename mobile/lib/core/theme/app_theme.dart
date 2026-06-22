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
  static const Color darkAccent = Color(0xFF58A6FF);
  static const Color darkHighlight = Color(0xFFF87171);

  // ─── Shared (theme-independent) ──────────────────────
  static const Color _primary = Color(0xFF1A1A2E);
  static const Color secondary = Color(0xFF16213E);
  static const Color _accent = Color(0xFF0F3460);
  static const Color _highlight = Color(0xFFE94560);
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

  static Color get primary =>
      _brightness == Brightness.dark ? darkPrimary : _primary;
  static Color get accent =>
      _brightness == Brightness.dark ? darkAccent : _accent;
  static Color get highlight =>
      _brightness == Brightness.dark ? darkHighlight : _highlight;

  /// Brightness-aware card background color.
  static Color get card =>
      _brightness == Brightness.dark ? darkCard : _surface;

  /// Consistent chart palette for category breakdowns and avatar fallbacks.
  static const List<Color> chartPalette = [
    Color(0xFFE94560), // red
    Color(0xFF0F3460), // navy
    Color(0xFF2ECC71), // green
    Color(0xFFF39C12), // amber
    Color(0xFF3498DB), // blue
    Color(0xFF9B59B6), // purple
    Color(0xFF1ABC9C), // teal
    Color(0xFFE67E22), // orange
    Color(0xFF34495E), // dark blue-grey
    Color(0xFF16A085), // dark teal
  ];

  /// Deterministic avatar color from a hash of the user name.
  static Color avatarColor(String name) {
    final hash = name.hashCode.abs();
    return chartPalette[hash % chartPalette.length];
  }

  /// Brightness-aware avatar background
  static Color avatarBackground(String name) {
    return avatarColor(name).withOpacity(_brightness == Brightness.dark ? 0.3 : 0.15);
  }

  /// Brightness-aware avatar text
  static Color avatarText(String name) {
    return _brightness == Brightness.dark ? AppColors.surface : avatarColor(name);
  }

  /// Brightness-aware highlight background for error containers
  static Color get highlightBackground =>
      highlight.withOpacity(_brightness == Brightness.dark ? 0.4 : 0.1);

  /// Brightness-aware credit card gradient
  static List<Color> get creditCardGradient => _brightness == Brightness.dark
      ? [darkSurface, darkCard]
      : [_primary, _accent];

  /// Brightness-aware selected color for category picker
  static Color get categoryPickerSelected => _brightness == Brightness.dark
      ? darkTextPrimary.withOpacity(0.12)
      : _primary.withOpacity(0.3);
}

class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        primaryColor: AppColors._primary,
        scaffoldBackgroundColor: AppColors._background,
        colorScheme: const ColorScheme.light(
          primary: AppColors._primary,
          secondary: AppColors._accent,
          surface: AppColors._surface,
          error: AppColors._highlight,
          onPrimary: AppColors._surface,
          onSecondary: AppColors._surface,
          onSurface: AppColors._textPrimary,
        ),
        cardColor: AppColors._surface,
        dividerColor: AppColors._divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors._primary,
          foregroundColor: AppColors._surface,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors._accent,
          foregroundColor: AppColors._surface,
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
            borderSide: BorderSide(color: AppColors._accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors._accent,
            foregroundColor: AppColors._surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors._surface,
          selectedItemColor: AppColors._accent,
          unselectedItemColor: AppColors._textSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors._surface,
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.darkPrimary,
        scaffoldBackgroundColor: AppColors.darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkPrimary,
          secondary: AppColors.darkAccent,
          surface: AppColors.darkSurface,
          error: AppColors.darkHighlight,
          onPrimary: AppColors.darkSurface,
          onSecondary: AppColors.darkSurface,
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
          backgroundColor: AppColors.darkAccent,
          foregroundColor: AppColors.darkSurface,
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
            backgroundColor: AppColors.darkAccent,
            foregroundColor: AppColors.darkSurface,
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
          selectedItemColor: AppColors.darkPrimary,
          unselectedItemColor: AppColors.darkTextSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkSurface,
        ),
      );
}
