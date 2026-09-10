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

  static Color get background => _t('background', _dark ? darkBackground : _background);
  static Color get surface => _t('surface', _dark ? darkSurface : _surface);
  static Color get textPrimary => _t('ink', _dark ? darkTextPrimary : _textPrimary);
  static Color get textSecondary => _t('muted', _dark ? darkTextSecondary : _textSecondary);
  static Color get divider => _t('line', _dark ? darkDivider : _divider);
  static Color get primary => _t('ink', _dark ? darkPrimary : _primary);
  static Color get accent => _t('accent', _dark ? darkAccent : _accent);
  static Color get highlight => _t('expense', _dark ? darkHighlight : _highlight);
  static Color get success => _t('income', _dark ? darkSuccess : _success);
  static Color get warning => _t('warning', _dark ? darkWarning : _warning);
  static Color get heroFill => _t('heroFill', _dark ? darkCard : _heroFill);
  static Color get heroOn => _t('heroOn', _dark ? darkTextPrimary : _onAccent);
  static Color get mint => _t('mint', _dark ? darkMint : _mint);
  static Color get butter => _t('butter', _dark ? darkButter : _butter);
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

  static Map<String, Color> _remoteLight = {};
  static Map<String, Color> _remoteDark = {};

  static Color? _hex(dynamic raw) {
    if (raw == null) return null;
    var h = raw.toString().trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    return Color(int.parse(h, radix: 16));
  }

  static void applyRemote({
    Map<String, dynamic>? light,
    Map<String, dynamic>? dark,
  }) {
    Color? tok(Map<String, dynamic>? src, String key) =>
        src == null ? null : _hex(src[key]);

    _remoteLight = {
      if (tok(light, 'background') != null) 'background': tok(light, 'background')!,
      if (tok(light, 'surface') != null) 'surface': tok(light, 'surface')!,
      if (tok(light, 'ink') != null) 'ink': tok(light, 'ink')!,
      if (tok(light, 'muted') != null) 'muted': tok(light, 'muted')!,
      if (tok(light, 'line') != null) 'line': tok(light, 'line')!,
      if (tok(light, 'accent') != null) 'accent': tok(light, 'accent')!,
      if (tok(light, 'expense') != null) 'expense': tok(light, 'expense')!,
      if (tok(light, 'income') != null) 'income': tok(light, 'income')!,
      if (tok(light, 'warning') != null) 'warning': tok(light, 'warning')!,
      if (tok(light, 'heroFill') != null) 'heroFill': tok(light, 'heroFill')!,
      if (tok(light, 'heroOn') != null) 'heroOn': tok(light, 'heroOn')!,
      if (tok(light, 'mint') != null) 'mint': tok(light, 'mint')!,
      if (tok(light, 'butter') != null) 'butter': tok(light, 'butter')!,
    };
    _remoteDark = {
      if (tok(dark, 'background') != null) 'background': tok(dark, 'background')!,
      if (tok(dark, 'surface') != null) 'surface': tok(dark, 'surface')!,
      if (tok(dark, 'ink') != null) 'ink': tok(dark, 'ink')!,
      if (tok(dark, 'muted') != null) 'muted': tok(dark, 'muted')!,
      if (tok(dark, 'line') != null) 'line': tok(dark, 'line')!,
      if (tok(dark, 'accent') != null) 'accent': tok(dark, 'accent')!,
      if (tok(dark, 'expense') != null) 'expense': tok(dark, 'expense')!,
      if (tok(dark, 'income') != null) 'income': tok(dark, 'income')!,
      if (tok(dark, 'warning') != null) 'warning': tok(dark, 'warning')!,
      if (tok(dark, 'heroFill') != null) 'heroFill': tok(dark, 'heroFill')!,
      if (tok(dark, 'heroOn') != null) 'heroOn': tok(dark, 'heroOn')!,
      if (tok(dark, 'mint') != null) 'mint': tok(dark, 'mint')!,
      if (tok(dark, 'butter') != null) 'butter': tok(dark, 'butter')!,
    };
  }

  static Color _t(String name, Color fallback) {
    final map = _dark ? _remoteDark : _remoteLight;
    return map[name] ?? fallback;
  }
}

class AppTheme {
  static const String fontFamily = 'Nunito';

  // NOTE: theme + darkTheme read the remote-aware AppColors getters
  // (server-driven presets).  AppColors.sync() must run before the
  // MaterialApp build so _dark resolves the correct palette.

  static ButtonStyle get segmentedButtonStyle => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return AppColors.card;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onAccent;
          return AppColors.textPrimary;
        }),
        overlayColor: WidgetStateProperty.all(AppColors.accent.withOpacity(0.16)),
        side: WidgetStateProperty.all(BorderSide(color: AppColors.divider)),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onAccent;
          return AppColors.textPrimary;
        }),
      );

  static DatePickerThemeData get datePicker => DatePickerThemeData(
        backgroundColor: AppColors.surface,
        headerBackgroundColor: AppColors.accent,
        headerForegroundColor: AppColors.onAccent,
        surfaceTintColor: Colors.transparent,
        dayForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.onAccent;
          if (s.contains(WidgetState.disabled)) {
            return AppColors.textSecondary.withOpacity(0.35);
          }
          return AppColors.textPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.accent;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.onAccent;
          return AppColors.accent;
        }),
        todayBackgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.accent;
          return Colors.transparent;
        }),
        yearForegroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.onAccent;
          return AppColors.textPrimary;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return AppColors.accent;
          return Colors.transparent;
        }),
        weekdayStyle: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        dayOverlayColor: WidgetStateProperty.all(AppColors.accent.withOpacity(0.14)),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        fontFamily: fontFamily,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.highlight,
          onPrimary: AppColors.surface,
          onSecondary: AppColors.textPrimary,
          onSurface: AppColors.textPrimary,
        ),
        cardColor: AppColors.surface,
        dividerColor: AppColors.divider,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textPrimary,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.background,
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.7)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            disabledForegroundColor: AppColors.onAccent.withOpacity(0.5),
            disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
            textStyle: TextStyle(
              fontFamily: fontFamily,
              color: AppColors.onAccent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.textPrimary,
          unselectedItemColor: AppColors.textSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
        ),
        datePickerTheme: datePicker,
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(style: segmentedButtonStyle),
      );

  // Dark theme. AppColors getters resolve the dark remote tokens when
  // _dark is true (AppColors.sync() in app.dart), so this block simply
  // reuses the same getters with a dark brightness.
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.highlight,
          onPrimary: AppColors.textPrimary,
          onSecondary: AppColors.textPrimary,
          onSurface: AppColors.textPrimary,
        ),
        cardColor: AppColors.surface,
        dividerColor: AppColors.divider,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textPrimary,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          labelStyle: TextStyle(color: AppColors.textSecondary),
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
          floatingLabelStyle: TextStyle(color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36, minHeight: 20, maxWidth: 44, maxHeight: 36),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            disabledForegroundColor: AppColors.onAccent.withOpacity(0.5),
            disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
            textStyle: TextStyle(
              fontFamily: fontFamily,
              color: AppColors.onAccent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.textPrimary,
          unselectedItemColor: AppColors.textSecondary,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
        ),
        datePickerTheme: datePicker,
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(style: segmentedButtonStyle),
      );
}
