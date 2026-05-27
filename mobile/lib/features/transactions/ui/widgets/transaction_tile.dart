import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';
import '../../../../shared/utils/category_translator.dart';
import '../../models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onTransferOwner;
  const TransactionTile({super.key, required this.transaction, this.onTransferOwner});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final icon = transaction.category.icon.isNotEmpty ? transaction.category.icon : '📦';
    final translatedCategory = translateCategory(transaction.category.name);
    final description = transaction.description;
    final ownerName = transaction.user?.displayName ?? '';

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
        '${translatedCategory.isEmpty ? "" : "$translatedCategory · "}${formatDateRelative(transaction.date)}${ownerName.isNotEmpty ? " · $ownerName" : ""}',
        style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isExpense ? "-" : "+"}${formatCurrency(transaction.amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isExpense ? AppColors.highlight : AppColors.success,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
            padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'edit') {
                context.push('/transactions/add', extra: transaction);
              } else if (value == 'change_owner') {
                onTransferOwner!();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
              if (onTransferOwner != null)
                const PopupMenuItem(
                  value: 'change_owner',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 18),
                      SizedBox(width: 8),
                      Text('Change Owner'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
