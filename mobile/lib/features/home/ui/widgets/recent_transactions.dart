import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../transactions/models/transaction_model.dart';
import '../../../transactions/ui/widgets/transaction_tile.dart';

class RecentTransactions extends StatelessWidget {
  final List<TransactionModel> transactions;
  const RecentTransactions({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Transactions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        if (transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No transactions this month', style: TextStyle(color: AppColors.textSecondary))),
            ),
          )
        else ...[
          Card(
            child: Column(
              children: [
                for (var i = 0; i < transactions.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  TransactionTile(transaction: transactions[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/transactions'),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('View All'), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ],
      ],
    );
  }
}