import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_theme.dart';

/// Map emoji category icons to Hugeicons. Falls back to a receipt glyph.
class CategoryGlyph extends StatelessWidget {
  final String icon;
  final bool expense;
  final double size;
  const CategoryGlyph({
    super.key,
    required this.icon,
    this.expense = true,
    this.size = 36,
  });

  List<List<dynamic>> get _mapped {
    switch (icon.trim()) {
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
      default:
        return HugeIcons.strokeRoundedInvoice01;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = expense ? AppColors.highlight : AppColors.success;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: HugeIcon(
        icon: _mapped,
        size: size * 0.5,
        color: tint,
      ),
    );
  }
}
