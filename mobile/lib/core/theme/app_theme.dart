import 'package:flutter/material.dart';

class AppColors {
  // ─── Light — Pastel cozy (docs/20) ───────────────────
  static const Color _background = Color(0xFFFFF3EE);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _textPrimary = Color(0xFF4A3A48);
  static const Color _textSecondary = Color(0xFF9B8794);
  static const Color _divider = Color(0xFFF3E0D8);
  static const Color _card = Color(0xFFFFE8DC);

  // ─── Dark ────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF2A2430);
  static const Color darkSurface = Color(0xFF3A3242);
  static const Color darkCard = Color(0xFF463848);
  static const Color darkTextPrimary = Color(0xFFF7EEE8);
  static const Color darkTextSecondary = Color(0xFFC4B4BE);
  static const Color darkDivider = Color(0xFF4C4354);
  static const Color darkPrimary = Color(0xFFE9A0B2);
  static const Color darkAccent = Color(0xFFE9A0B2);
  static const Color darkHighlight = Color(0xFFF0A090);

  static const Color _primary = Color(0xFF4A3A48);
  static const Color secondary = Color(0xFFD4C4F0);
  static const Color _accent = Color(0xFFF3A6B8);
  static const Color _highlight = Color(0xFFE08B7C);
  static const Color _success = Color(0xFF4EAE90);
  static const Color darkSuccess = Color(0xFF7ED0B4);
  static const Color _warning = Color(0xFFE8B86D);
  static const Color darkWarning = Color(0xFFE8C47A);
  static const Color _heroFill = Color(0xFFFFE8DC);
  static const Color _onAccent = Color(0xFF4A3A48);

  static Color get onAccent => _onAccent;
  static const Color _mint = Color(0xFF9DD9C0);
  static const Color darkMint = Color(0xFF8FCFB6);
  static const Color _butter = Color(0xFFF6E3A1);
  static const Color darkButter = Color(0xFFE8D28A);

  static Brightness _brightness = Brightness.light;

  static void sync(Brightness b) => _brightness = b;

  static bool get _dark => _brightness == Brightness.dark;

  static Color get background => _dark ? darkBackground : _background;
  static Color get surface => _dark ? darkSurface : _surface;
  static Color get textPrimary => _dark ? darkTextPrimary : _textPrimary;
  static Color get textSecondary => _dark ? darkTextSecondary : _textSecondary;
  static Color get divider => _dark ? darkDivider : _divider;
  static Color get primary => _dark ? darkPrimary : _primary;
  static Color get accent => _dark ? darkAccent : _accent;
  static Color get highlight => _dark ? darkHighlight : _highlight;
  static Color get success => _dark ? darkSuccess : _success;
  static Color get warning => _dark ? darkWarning : _warning;
  static Color get heroFill => _dark ? darkCard : _heroFill;
  static Color get heroOn => _dark ? darkTextPrimary : _onAccent;
  static Color get mint => _dark ? darkMint : _mint;
  static Color get butter => _dark ? darkButter : _butter;
  static Color get card => _dark ? darkCard : _surface;
  static Color get navActive => _dark ? darkTextPrimary : _textPrimary;
  static Color get navInactive => _dark ? darkTextSecondary : _textSecondary;

  static const List<Color> chartPalette = [
    Color(0xFFF3A6B8),
    Color(0xFF9DD9C0),
    Color(0xFFD4C4F0),
    Color(0xFFF6E3A1),
    Color(0xFFFFD0B8),
    Color(0xFFE08B7C),
    Color(0xFF4EAE90),
    Color(0xFFC9E4F5),
    Color(0xFFE9A0B2),
    Color(0xFF8FCFB6),
  ];

  static Color avatarColor(String name) {
    final hash = name.hashCode.abs();
    return chartPalette[hash % chartPalette.length];
  }

  static Color avatarBackground(String name) {
    return avatarColor(name).withOpacity(_dark ? 0.35 : 0.42);
  }

  static Color avatarText(String name) =>
      _dark ? avatarColor(name) : _textPrimary;

  static Color get highlightBackground =>
      highlight.withOpacity(_dark ? 0.4 : 0.1);

  static List<Color> get creditCardGradient =>
      _dark ? [darkSurface, darkCard] : [_surface, _card];

  static Color get categoryPickerSelected =>
      _dark ? darkTextPrimary.withOpacity(0.12) : _primary.withOpacity(0.3);
}

class AppTheme {
  static const String fontFamily = 'Nunito';

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        fontFamily: fontFamily,
        primaryColor: AppColors._primary,
        scaffoldBackgroundColor: AppColors._background,
        colorScheme: const ColorScheme.light(
          primary: AppColors._primary,
          secondary: AppColors._accent,
          surface: AppColors._surface,
          error: AppColors._highlight,
          onPrimary: AppColors._surface,
          onSecondary: AppColors._textPrimary,
          onSurface: AppColors._textPrimary,
        ),
        cardColor: AppColors._surface,
        dividerColor: AppColors._divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors._background,
          foregroundColor: AppColors._textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors._textPrimary,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors._accent,
          foregroundColor: AppColors._textPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors._background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors._divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors._divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors._accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors._accent,
            foregroundColor: AppColors._onAccent,
            disabledForegroundColor: AppColors._onAccent.withOpacity(0.5),
            disabledBackgroundColor: AppColors._accent.withOpacity(0.5),
            textStyle: const TextStyle(
              fontFamily: fontFamily,
              color: AppColors._onAccent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors._surface,
          selectedItemColor: AppColors._textPrimary,
          unselectedItemColor: AppColors._textSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors._surface,
        ),
        cardTheme: CardThemeData(
          color: AppColors._surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        primaryColor: AppColors.darkPrimary,
        scaffoldBackgroundColor: AppColors.darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkPrimary,
          secondary: AppColors.darkAccent,
          surface: AppColors.darkSurface,
          error: AppColors.darkHighlight,
          onPrimary: AppColors.darkTextPrimary,
          onSecondary: AppColors.darkTextPrimary,
          onSurface: AppColors.darkTextPrimary,
        ),
        cardColor: AppColors.darkSurface,
        dividerColor: AppColors.darkDivider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBackground,
          foregroundColor: AppColors.darkTextPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.darkTextPrimary,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.darkAccent,
          foregroundColor: AppColors.darkTextPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          labelStyle: TextStyle(color: AppColors.darkTextSecondary),
          hintStyle: TextStyle(color: AppColors.darkTextSecondary.withOpacity(0.6)),
          floatingLabelStyle: TextStyle(color: AppColors.darkPrimary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.darkDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.darkDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.darkPrimary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors._accent,
            foregroundColor: AppColors._onAccent,
            disabledForegroundColor: AppColors._onAccent.withOpacity(0.5),
            disabledBackgroundColor: AppColors._accent.withOpacity(0.5),
            textStyle: const TextStyle(
              fontFamily: fontFamily,
              color: AppColors._onAccent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
          selectedItemColor: AppColors.darkTextPrimary,
          unselectedItemColor: AppColors.darkTextSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkSurface,
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      );
}
