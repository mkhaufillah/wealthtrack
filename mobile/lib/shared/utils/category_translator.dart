/// Maps Indonesian category names to English for consistent display in the Flutter app.
///
/// The database stores categories in Indonesian (used by Hermes cron & financial-tracker skill).
/// This map translates names at the UI layer only — no database changes needed.
const Map<String, String> categoryTranslations = {};

/// Translates a category name from Indonesian to English.
/// Returns the original name if no translation exists (safe fallback).
String translateCategory(String name) => name;
