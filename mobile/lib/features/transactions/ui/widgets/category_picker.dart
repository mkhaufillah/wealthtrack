import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/category_glyph.dart';
import '../../../../core/ui/copy_fallback.dart';

class CategoryChip {
  final int id;
  final String name;
  final String icon;
  final String copyKey;
  const CategoryChip({
    required this.id,
    required this.name,
    required this.icon,
    this.copyKey = '',
  });
}

class CategoryPicker extends StatelessWidget {
  final List<CategoryChip> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;
  final bool isExpense;
  const CategoryPicker({
    super.key,
    required this.categories,
    this.selectedId,
    required this.onSelected,
    this.isExpense = true,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(
        t('cat.empty_picker'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      );
    }
    final selectedTint = isExpense ? AppColors.highlight : AppColors.success;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final cat in categories)
          _CatChip(
            label: catLabel(name: cat.name, copyKey: cat.copyKey),
            icon: cat.icon,
            selected: cat.id == selectedId,
            selectedTint: selectedTint,
            expense: isExpense,
            onTap: () => onSelected(cat.id),
          ),
      ],
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final String icon;
  final bool selected;
  final Color selectedTint;
  final bool expense;
  final VoidCallback onTap;
  const _CatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedTint,
    required this.expense,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: selected ? selectedTint.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? selectedTint.withOpacity(0.55) : AppColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryGlyph(icon: icon, expense: expense, size: 24, selected: selected),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? selectedTint : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
