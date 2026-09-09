import 'copy_fallback.dart';
import 'package:hugeicons/hugeicons.dart';

/// Curated Hugeicons keys stored in `categories.icon`.
/// Only names that exist in hugeicons 1.1.7.
class CategoryIconItem {
  final String key;
  final String copyKey;
  final List<List<dynamic>> icon;
  const CategoryIconItem(this.key, this.copyKey, this.icon);
  String get label => t(copyKey);
  bool matchesQuery(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return key.toLowerCase().contains(needle) ||
        (copyFallback[copyKey] ?? '').toLowerCase().contains(needle) ||
        (copyFallbackEn[copyKey] ?? '').toLowerCase().contains(needle);
  }
}

const kDefaultCategoryIcon = 'strokeRoundedInvoice01';

final List<CategoryIconItem> kCategoryIconCatalog = [
  CategoryIconItem('strokeRoundedServingFood', 'icon.food', HugeIcons.strokeRoundedServingFood),
  CategoryIconItem('strokeRoundedCar01', 'icon.car', HugeIcons.strokeRoundedCar01),
  CategoryIconItem('strokeRoundedFuelStation', 'icon.fuel', HugeIcons.strokeRoundedFuelStation),
  CategoryIconItem('strokeRoundedShoppingBag01', 'icon.shop', HugeIcons.strokeRoundedShoppingBag01),
  CategoryIconItem('strokeRoundedHome01', 'icon.bills', HugeIcons.strokeRoundedHome01),
  CategoryIconItem('strokeRoundedHouse01', 'icon.home', HugeIcons.strokeRoundedHouse01),
  CategoryIconItem('strokeRoundedMedicineBottle01', 'icon.health', HugeIcons.strokeRoundedMedicineBottle01),
  CategoryIconItem('strokeRoundedSchool', 'icon.school', HugeIcons.strokeRoundedSchool),
  CategoryIconItem('strokeRoundedGameController01', 'icon.game', HugeIcons.strokeRoundedGameController01),
  CategoryIconItem('strokeRoundedTv01', 'icon.fun', HugeIcons.strokeRoundedTv01),
  CategoryIconItem('strokeRoundedMoneyBag01', 'icon.money', HugeIcons.strokeRoundedMoneyBag01),
  CategoryIconItem('strokeRoundedBank', 'icon.bank', HugeIcons.strokeRoundedBank),
  CategoryIconItem('strokeRoundedSmartPhone01', 'icon.phone', HugeIcons.strokeRoundedSmartPhone01),
  CategoryIconItem('strokeRoundedLaptop', 'icon.laptop', HugeIcons.strokeRoundedLaptop),
  CategoryIconItem('strokeRoundedClothes', 'icon.clothes', HugeIcons.strokeRoundedClothes),
  CategoryIconItem('strokeRoundedGift', 'icon.gift', HugeIcons.strokeRoundedGift),
  CategoryIconItem('strokeRoundedAirplane01', 'icon.plane', HugeIcons.strokeRoundedAirplane01),
  CategoryIconItem('strokeRoundedFishFood', 'icon.pets', HugeIcons.strokeRoundedFishFood),
  CategoryIconItem('strokeRoundedInvoice01', 'icon.receipt', HugeIcons.strokeRoundedInvoice01),
  CategoryIconItem('strokeRoundedExchange01', 'icon.transfer', HugeIcons.strokeRoundedExchange01),
  CategoryIconItem('strokeRoundedWallet01', 'icon.wallet', HugeIcons.strokeRoundedWallet01),
  CategoryIconItem('strokeRoundedPiggyBank', 'icon.piggy', HugeIcons.strokeRoundedPiggyBank),
  CategoryIconItem('strokeRoundedCreditCard', 'icon.card', HugeIcons.strokeRoundedCreditCard),
  CategoryIconItem('strokeRoundedCalendar01', 'icon.calendar', HugeIcons.strokeRoundedCalendar01),
  CategoryIconItem('strokeRoundedUser', 'icon.person', HugeIcons.strokeRoundedUser),
  CategoryIconItem('strokeRoundedShield01', 'icon.shield', HugeIcons.strokeRoundedShield01),
  CategoryIconItem('strokeRoundedSparkles', 'icon.other', HugeIcons.strokeRoundedSparkles),
  CategoryIconItem('strokeRoundedBaby01', 'icon.baby', HugeIcons.strokeRoundedBaby01),
  CategoryIconItem('strokeRoundedBabyBottle', 'icon.milk', HugeIcons.strokeRoundedBabyBottle),
  CategoryIconItem('strokeRoundedCoffee01', 'icon.coffee', HugeIcons.strokeRoundedCoffee01),
  CategoryIconItem('strokeRoundedBus01', 'icon.bus', HugeIcons.strokeRoundedBus01),
  CategoryIconItem('strokeRoundedBicycle', 'icon.bike', HugeIcons.strokeRoundedBicycle),
  CategoryIconItem('strokeRoundedBriefcase01', 'icon.work', HugeIcons.strokeRoundedBriefcase01),
  CategoryIconItem('strokeRoundedBed', 'icon.bed', HugeIcons.strokeRoundedBed),
  CategoryIconItem('strokeRoundedDumbbell01', 'icon.sport', HugeIcons.strokeRoundedDumbbell01),
  CategoryIconItem('strokeRoundedFavourite', 'icon.fav', HugeIcons.strokeRoundedFavourite),
  CategoryIconItem('strokeRoundedFirstAidKit', 'icon.firstaid', HugeIcons.strokeRoundedFirstAidKit),
  CategoryIconItem('strokeRoundedFootball', 'icon.ball', HugeIcons.strokeRoundedFootball),
  CategoryIconItem('strokeRoundedBasketball01', 'icon.basket', HugeIcons.strokeRoundedBasketball01),
  CategoryIconItem('strokeRoundedDroplet', 'icon.water', HugeIcons.strokeRoundedDroplet),
  CategoryIconItem('strokeRoundedSun01', 'icon.sun', HugeIcons.strokeRoundedSun01),
  CategoryIconItem('strokeRoundedMoon02', 'icon.moon', HugeIcons.strokeRoundedMoon02),
  CategoryIconItem('strokeRoundedCopy01', 'icon.copy', HugeIcons.strokeRoundedCopy01),
  CategoryIconItem('strokeRoundedNoodles', 'icon.noodles', HugeIcons.strokeRoundedNoodles),
  CategoryIconItem('strokeRoundedRestaurant01', 'icon.resto', HugeIcons.strokeRoundedRestaurant01),
  CategoryIconItem('strokeRoundedHospital01', 'icon.hospital', HugeIcons.strokeRoundedHospital01),
  CategoryIconItem('strokeRoundedBook01', 'icon.book', HugeIcons.strokeRoundedBook01),
  CategoryIconItem('strokeRoundedStudent', 'icon.student', HugeIcons.strokeRoundedStudent),
  CategoryIconItem('strokeRoundedComputer', 'icon.computer', HugeIcons.strokeRoundedComputer),
  CategoryIconItem('strokeRoundedCamera01', 'icon.camera', HugeIcons.strokeRoundedCamera01),
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
