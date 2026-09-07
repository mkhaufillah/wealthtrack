import 'package:hugeicons/hugeicons.dart';

/// Curated Hugeicons keys stored in `categories.icon`.
/// Only names that exist in hugeicons 1.1.7.
class CategoryIconItem {
  final String key;
  final String label;
  final List<List<dynamic>> icon;
  const CategoryIconItem(this.key, this.label, this.icon);
}

const kDefaultCategoryIcon = 'strokeRoundedInvoice01';

final List<CategoryIconItem> kCategoryIconCatalog = [
  CategoryIconItem('strokeRoundedServingFood', 'Makan', HugeIcons.strokeRoundedServingFood),
  CategoryIconItem('strokeRoundedCar01', 'Mobil', HugeIcons.strokeRoundedCar01),
  CategoryIconItem('strokeRoundedFuelStation', 'Bensin', HugeIcons.strokeRoundedFuelStation),
  CategoryIconItem('strokeRoundedShoppingBag01', 'Belanja', HugeIcons.strokeRoundedShoppingBag01),
  CategoryIconItem('strokeRoundedHome01', 'Tagihan', HugeIcons.strokeRoundedHome01),
  CategoryIconItem('strokeRoundedHouse01', 'Rumah', HugeIcons.strokeRoundedHouse01),
  CategoryIconItem('strokeRoundedMedicineBottle01', 'Kesehatan', HugeIcons.strokeRoundedMedicineBottle01),
  CategoryIconItem('strokeRoundedSchool', 'Sekolah', HugeIcons.strokeRoundedSchool),
  CategoryIconItem('strokeRoundedGameController01', 'Game', HugeIcons.strokeRoundedGameController01),
  CategoryIconItem('strokeRoundedTv01', 'Hiburan', HugeIcons.strokeRoundedTv01),
  CategoryIconItem('strokeRoundedMoneyBag01', 'Uang', HugeIcons.strokeRoundedMoneyBag01),
  CategoryIconItem('strokeRoundedBank', 'Bank', HugeIcons.strokeRoundedBank),
  CategoryIconItem('strokeRoundedSmartPhone01', 'HP', HugeIcons.strokeRoundedSmartPhone01),
  CategoryIconItem('strokeRoundedLaptop', 'Laptop', HugeIcons.strokeRoundedLaptop),
  CategoryIconItem('strokeRoundedClothes', 'Baju', HugeIcons.strokeRoundedClothes),
  CategoryIconItem('strokeRoundedGift', 'Kado', HugeIcons.strokeRoundedGift),
  CategoryIconItem('strokeRoundedAirplane01', 'Pesawat', HugeIcons.strokeRoundedAirplane01),
  CategoryIconItem('strokeRoundedFishFood', 'Hewan', HugeIcons.strokeRoundedFishFood),
  CategoryIconItem('strokeRoundedInvoice01', 'Struk', HugeIcons.strokeRoundedInvoice01),
  CategoryIconItem('strokeRoundedExchange01', 'Transfer', HugeIcons.strokeRoundedExchange01),
  CategoryIconItem('strokeRoundedWallet01', 'Dompet', HugeIcons.strokeRoundedWallet01),
  CategoryIconItem('strokeRoundedPiggyBank', 'Celengan', HugeIcons.strokeRoundedPiggyBank),
  CategoryIconItem('strokeRoundedCreditCard', 'Kartu', HugeIcons.strokeRoundedCreditCard),
  CategoryIconItem('strokeRoundedCalendar01', 'Kalender', HugeIcons.strokeRoundedCalendar01),
  CategoryIconItem('strokeRoundedUser', 'Orang', HugeIcons.strokeRoundedUser),
  CategoryIconItem('strokeRoundedShield01', 'Proteksi', HugeIcons.strokeRoundedShield01),
  CategoryIconItem('strokeRoundedSparkles', 'Lainnya', HugeIcons.strokeRoundedSparkles),
];

final Map<String, List<List<dynamic>>> _byKey = {
  for (final i in kCategoryIconCatalog) i.key: i.icon,
};

/// Emoji leftovers (pre-migration) still resolve until DB is fully converted.
List<List<dynamic>> hugeIconFor(String raw) {
  final key = raw.trim();
  final mapped = _byKey[key];
  if (mapped != null) return mapped;
  switch (key) {
    case '🍔':
    case '🍜':
    case '🍱':
    case '🍽️':
    case '🍽':
      return HugeIcons.strokeRoundedServingFood;
    case '🚗':
    case '🛵':
      return HugeIcons.strokeRoundedCar01;
    case '⛽':
    case '⛽️':
      return HugeIcons.strokeRoundedFuelStation;
    case '🛒':
    case '🛍️':
      return HugeIcons.strokeRoundedShoppingBag01;
    case '💡':
    case '⚡':
      return HugeIcons.strokeRoundedHome01;
    case '🏥':
    case '💊':
      return HugeIcons.strokeRoundedMedicineBottle01;
    case '🎓':
      return HugeIcons.strokeRoundedSchool;
    case '🎮':
      return HugeIcons.strokeRoundedGameController01;
    case '💰':
    case '💵':
      return HugeIcons.strokeRoundedMoneyBag01;
    case '🏦':
      return HugeIcons.strokeRoundedBank;
    case '📱':
      return HugeIcons.strokeRoundedSmartPhone01;
    case '🏠':
      return HugeIcons.strokeRoundedHouse01;
    case '👕':
      return HugeIcons.strokeRoundedClothes;
    case '🎁':
      return HugeIcons.strokeRoundedGift;
    case '✈️':
    case '✈':
      return HugeIcons.strokeRoundedAirplane01;
    case '🐶':
    case '🐱':
      return HugeIcons.strokeRoundedFishFood;
    case '🎬':
      return HugeIcons.strokeRoundedTv01;
    case '📄':
      return HugeIcons.strokeRoundedInvoice01;
    case '💻':
      return HugeIcons.strokeRoundedLaptop;
    case '🔄':
      return HugeIcons.strokeRoundedExchange01;
    default:
      return HugeIcons.strokeRoundedInvoice01;
  }
}
