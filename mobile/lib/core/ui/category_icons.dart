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
  CategoryIconItem('strokeRoundedBaby01', 'Bayi', HugeIcons.strokeRoundedBaby01),
  CategoryIconItem('strokeRoundedBabyBottle', 'Susu', HugeIcons.strokeRoundedBabyBottle),
  CategoryIconItem('strokeRoundedCoffee01', 'Kopi', HugeIcons.strokeRoundedCoffee01),
  CategoryIconItem('strokeRoundedBus01', 'Bus', HugeIcons.strokeRoundedBus01),
  CategoryIconItem('strokeRoundedBicycle', 'Sepeda', HugeIcons.strokeRoundedBicycle),
  CategoryIconItem('strokeRoundedBriefcase01', 'Kerja', HugeIcons.strokeRoundedBriefcase01),
  CategoryIconItem('strokeRoundedBed', 'Kasur', HugeIcons.strokeRoundedBed),
  CategoryIconItem('strokeRoundedDumbbell01', 'Olahraga', HugeIcons.strokeRoundedDumbbell01),
  CategoryIconItem('strokeRoundedFavourite', 'Favorit', HugeIcons.strokeRoundedFavourite),
  CategoryIconItem('strokeRoundedFirstAidKit', 'P3K', HugeIcons.strokeRoundedFirstAidKit),
  CategoryIconItem('strokeRoundedFootball', 'Bola', HugeIcons.strokeRoundedFootball),
  CategoryIconItem('strokeRoundedBasketball01', 'Basket', HugeIcons.strokeRoundedBasketball01),
  CategoryIconItem('strokeRoundedDroplet', 'Air', HugeIcons.strokeRoundedDroplet),
  CategoryIconItem('strokeRoundedSun01', 'Matahari', HugeIcons.strokeRoundedSun01),
  CategoryIconItem('strokeRoundedMoon02', 'Bulan', HugeIcons.strokeRoundedMoon02),
  CategoryIconItem('strokeRoundedCopy01', 'Salin', HugeIcons.strokeRoundedCopy01),
  CategoryIconItem('strokeRoundedNoodles', 'Mie', HugeIcons.strokeRoundedNoodles),
  CategoryIconItem('strokeRoundedRestaurant01', 'Resto', HugeIcons.strokeRoundedRestaurant01),
  CategoryIconItem('strokeRoundedHospital01', 'RS', HugeIcons.strokeRoundedHospital01),
  CategoryIconItem('strokeRoundedBook01', 'Buku', HugeIcons.strokeRoundedBook01),
  CategoryIconItem('strokeRoundedStudent', 'Siswa', HugeIcons.strokeRoundedStudent),
  CategoryIconItem('strokeRoundedComputer', 'Komputer', HugeIcons.strokeRoundedComputer),
  CategoryIconItem('strokeRoundedCamera01', 'Kamera', HugeIcons.strokeRoundedCamera01),
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
