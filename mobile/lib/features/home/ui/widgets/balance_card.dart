import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';

class BalanceCard extends StatelessWidget {
  final int balance; final int income; final int expense;
  const BalanceCard({super.key, required this.balance, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('💰', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text('Monthly Balance', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatCurrency(balance),
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Divider(color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LabeledAmount(label: 'Income', amount: income, color: AppColors.success),
                Container(width: 1, height: 30, color: AppColors.divider),
                _LabeledAmount(label: 'Expense', amount: expense, color: AppColors.highlight),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledAmount extends StatelessWidget {
  final String label; final int amount; final Color color;
  const _LabeledAmount({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(formatCurrency(amount),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
