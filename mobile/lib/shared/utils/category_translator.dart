/// Maps Indonesian category names to English for consistent display in the Flutter app.
///
/// The database stores categories in Indonesian (used by Hermes cron & financial-tracker skill).
/// This map translates names at the UI layer only — no database changes needed.
const Map<String, String> categoryTranslations = {
  // Income
  'Gaji': 'Salary',
  'Freelance': 'Freelance',
  'Bonus & THR': 'Bonus & THR',
  'Investasi': 'Investment',
  'Lainnya': 'Other',

  // Expense
  'Makanan & Minuman': 'Food & Drinks',
  'Transportasi & Bensin': 'Transport & Fuel',
  'Belanja Harian': 'Daily Shopping',
  'Hiburan': 'Entertainment',
  'Tagihan & Cicilan': 'Bills & Installments',
  'Kesehatan': 'Health',
  'Pendidikan': 'Education',
  'Tabungan & Investasi': 'Savings & Investment',
  'Kebutuhan Bayi/Anak': 'Baby & Child Needs',
};

/// Translates a category name from Indonesian to English.
/// Returns the original name if no translation exists (safe fallback).
String translateCategory(String indonesianName) {
  return categoryTranslations[indonesianName] ?? indonesianName;
}
