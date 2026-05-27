import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';
import '../../../../shared/utils/category_translator.dart';
import '../../models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  const TransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final icon = transaction.category.icon.isNotEmpty ? transaction.category.icon : '📦';
    final translatedCategory = translateCategory(transaction.category.name);
    final description = transaction.description;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isExpense
              ? AppColors.highlight.withOpacity(0.1)
              : AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
      ),
      title: Text(
        description.isEmpty ? translatedCategory : description,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${translatedCategory.isEmpty ? "" : "$translatedCategory · "}${formatDateRelative(transaction.date)}',
        style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Text(
        '${isExpense ? "-" : "+"}${formatCurrency(transaction.amount)}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isExpense ? AppColors.highlight : AppColors.success,
        ),
      ),
    );
  }
}
