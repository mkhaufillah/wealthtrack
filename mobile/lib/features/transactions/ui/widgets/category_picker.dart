import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CategoryChip {
  final int id;
  final String name;
  final String nameEn;
  final String icon;
  const CategoryChip({
    required this.id,
    required this.name,
    this.nameEn = '',
    required this.icon,
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
        'Kategori belum ada',
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
            label: cat.name,
            selected: cat.id == selectedId,
            selectedTint: selectedTint,
            onTap: () => onSelected(cat.id),
          ),
      ],
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedTint;
  final VoidCallback onTap;
  const _CatChip({
    required this.label,
    required this.selected,
    required this.selectedTint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedTint.withOpacity(0.14) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? selectedTint : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
