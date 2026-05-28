import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/dashboard_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import 'widgets/balance_card.dart';
import 'widgets/recent_transactions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);

    // Reload dashboard when homeRefreshProvider is incremented
    ref.listen<int>(homeRefreshProvider, (prev, next) {
      if (prev != next) ref.read(dashboardProvider.notifier).load();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('WealthTrack')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).load(),
        child: state.isLoading
            ? const LoadingIndicator()
            : state.error != null
                ? ErrorDisplay(message: state.error!, onRetry: () => ref.read(dashboardProvider.notifier).load())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      BalanceCard(
                        balance: state.balance,
                        income: state.totalIncome,
                        expense: state.totalExpense,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _StatCard(
                            icon: Icons.arrow_upward, label: 'Income',
                            amount: state.totalIncome, color: AppColors.success,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _StatCard(
                            icon: Icons.arrow_downward, label: 'Expense',
                            amount: state.totalExpense, color: AppColors.highlight,
                          )),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildAiCard(),
                      const SizedBox(height: 24),
                      RecentTransactions(transactions: state.recentTransactions),
                    ],
                  ),
      ),
    );
  }
  Widget _buildAiCard() {
    return Card(
      color: AppColors.accent.withOpacity(0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/ai/advise'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.psychology_outlined, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Financial Advisor',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Ask anything about your finances',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label; final int amount; final Color color;
  const _StatCard({required this.icon, required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text(formatCurrency(amount),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}