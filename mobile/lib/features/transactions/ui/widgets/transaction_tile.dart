import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';

class TransactionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const TransactionTile({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isExpense = data['type'] == 'expense';
    final icon = data['category']?['icon'] as String? ?? '📦';
    final categoryName = data['category']?['name'] as String? ?? '';
    final amount = data['amount'] as int;
    final description = data['description'] as String? ?? '';
    final date = data['date'] as String? ?? '';

    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isExpense ? AppColors.highlight.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
      ),
      title: Text(description.isEmpty ? categoryName : description,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text('${categoryName.isEmpty ? "" : "$categoryName · "}${formatDateRelative(date)}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Text('${isExpense ? "-" : "+"}${formatCurrency(amount)}',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: isExpense ? AppColors.highlight : AppColors.success)),
    );
  }
}