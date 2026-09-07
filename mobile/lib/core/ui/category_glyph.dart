import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Category emoji in a pastel well — not a naked glyph on white.
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
    final glyph = icon.trim().isEmpty ? '·' : icon.trim();
    final tint = expense ? AppColors.highlight : AppColors.success;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        glyph,
        style: TextStyle(fontSize: size * 0.42, height: 1),
      ),
    );
  }
}
