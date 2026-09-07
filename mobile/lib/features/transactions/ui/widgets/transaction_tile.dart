import 'package:flutter/material.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';
import '../../data/transaction_repository.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onTransferOwner;
  final VoidCallback? onDelete;
  final bool showActions;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTransferOwner,
    this.onDelete,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final icon = transaction.category.icon.isNotEmpty ? transaction.category.icon : '📦';
    final translatedCategory = transaction.category.nameEn.isNotEmpty
        ? transaction.category.nameEn
        : transaction.category.name;
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
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${translatedCategory.isEmpty ? "" : "$translatedCategory · "}${formatDateRelative(transaction.date)}${ownerName.isNotEmpty ? " · $ownerName" : ""}',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          if (showActions) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: AppIcon(AppIcons.more, size: 18, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') {
                  context.push('/transactions/add', extra: transaction);
                } else if (value == 'change_owner') {
                  onTransferOwner!();
                } else if (value == 'delete') {
                  onDelete!();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      AppIcon(AppIcons.edit, size: 18),
                      const SizedBox(width: 8),
                      const Text('Edit'),
                    ],
                  ),
                ),
                if (onTransferOwner != null)
                  PopupMenuItem(
                    value: 'change_owner',
                    child: Row(
                      children: [
                        AppIcon(AppIcons.swap, size: 18),
                        const SizedBox(width: 8),
                        const Text('Change Owner'),
                      ],
                    ),
                  ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        AppIcon(AppIcons.trash, size: 18),
                        const SizedBox(width: 8),
                        const Text('Delete'),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
