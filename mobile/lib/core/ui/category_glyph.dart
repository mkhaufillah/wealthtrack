import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_theme.dart';
import 'category_icons.dart';

/// Render a category icon from a Hugeicons DB key (or leftover emoji).
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
        icon: hugeIconFor(icon),
        size: size * 0.5,
        color: tint,
      ),
    );
  }
}
