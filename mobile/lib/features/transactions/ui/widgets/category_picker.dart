import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/category_translator.dart';

class CategoryChip {
  final int id;
  final String name;
  final String icon;
  const CategoryChip(
      {required this.id, required this.name, required this.icon});
}

class CategoryPicker extends StatelessWidget {
  final List<CategoryChip> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;
  const CategoryPicker(
      {super.key,
      required this.categories,
      this.selectedId,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = cat.id == selectedId;
          return FilterChip(
            label: Text('${cat.icon} ${translateCategory(cat.name)}'),
            selected: isSelected,
            onSelected: (_) => onSelected(cat.id),
            selectedColor: isDark
                ? AppColors.textPrimary.withOpacity(0.12)
                : AppColors.primary.withOpacity(0.3),
            checkmarkColor: AppColors.textPrimary,
          );
        },
      ),
    );
  }
}
