import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../../shared/providers/app_providers.dart';
import 'widgets/balance_card.dart';
import 'widgets/recent_transactions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _savingsBalance = 0;
  int _emergencyBalance = 0;

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd MMM').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).load());
    Future.microtask(() => _loadAllTimeBalances());
  }

  Future<void> _loadAllTimeBalances() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get('/summaries/all-time-category-balance');
      final data = resp.data as Map<String, dynamic>? ?? {};
      int savings = 0;
      int emergency = 0;

      final siData = data['savings_investment'];
      if (siData is Map) {
        savings = (siData['balance'] as num?)?.toInt() ?? 0;
      }

      final efData = data['emergency_funds'];
      if (efData is Map) {
        emergency = (efData['balance'] as num?)?.toInt() ?? 0;
      }

      if (mounted) {
        setState(() {
          _savingsBalance = savings;
          _emergencyBalance = emergency;
        });
      }
    } catch (_) {
      // Silently fail — the summary card is optional
    }
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
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                    children: [
                      BalanceCard(
                        balance: state.balance,
                        income: state.totalIncome,
                        expense: state.totalExpense,
                        cycleLabel: state.dateFrom != null && state.dateTo != null
                            ? '${_formatDate(state.dateFrom!)} – ${_formatDate(state.dateTo!)}'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      _buildCategoriesCard(),
                      const SizedBox(height: 24),
                      _buildAiCard(),
                      const SizedBox(height: 24),
                      RecentTransactions(transactions: state.recentTransactions),
                    ],
                  ),
      ),
    );
  }
  Widget _buildCategoriesCard() {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance_outlined,
                      color: AppColors.textPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('All-time Balances',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            _balanceRow('💳  Savings & Investment', _savingsBalance),
            const SizedBox(height: 8),
            _balanceRow('🆘  Emergency Funds', _emergencyBalance),
          ],
        ),
      ),
    );
  }

  Widget _balanceRow(String label, int amount) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Text(
          formatCurrency(amount),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: amount >= 0 ? AppColors.success : AppColors.highlight,
          ),
        ),
      ],
    );
  }

  Widget _buildAiCard() {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                child: Icon(Icons.psychology_outlined, color: Colors.white, size: 24),
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