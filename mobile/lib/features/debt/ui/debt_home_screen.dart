import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class DebtHomeScreen extends StatelessWidget {
  const DebtHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Debt Tracker'),
      ),
      body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // KPR Card
            _buildDebtCard(
              context: context,
              imagePath: 'assets/images/debt/mortgage_illustration.png',
              title: 'Mortgage (KPR)',
              description: 'Calculate and simulate mortgage payments with various interest rate types',
              onTap: () => context.go('/debt/kpr'),
            ),
            const SizedBox(height: 16),
            // Credit Card Card
            _buildDebtCard(
              context: context,
              imagePath: 'assets/images/debt/credit_card_illustration.png',
              title: 'Credit Cards',
              description: 'Track credit card spending, installments, and upcoming payments',
              onTap: () => context.go('/debt/credit-cards'),
            ),
          ],
        ),
      );
  }

  Widget _buildDebtCard({
    required BuildContext context,
    required String imagePath,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.divider.withAlpha(40),
                  child: Center(
                    child: Icon(Icons.image_outlined, size: 48, color: AppColors.textSecondary.withAlpha(100)),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
