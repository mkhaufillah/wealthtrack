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
      color: AppColors.secondary,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('💰', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            const Text('Monthly Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(formatCurrency(balance),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LabeledAmount(label: 'Income', amount: income, color: AppColors.success),
                Container(width: 1, height: 30, color: Colors.white24),
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
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(formatCurrency(amount),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}