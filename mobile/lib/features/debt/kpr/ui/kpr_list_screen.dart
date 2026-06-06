import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kpr_provider.dart';
import '../../models/kpr_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../core/theme/app_theme.dart';

class KPRListScreen extends ConsumerStatefulWidget {
  const KPRListScreen({super.key});

  @override
  ConsumerState<KPRListScreen> createState() => _KPRListScreenState();
}

class _KPRListScreenState extends ConsumerState<KPRListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(kprProvider.notifier).loadAll());
  }

  Future<void> _onRefresh() async {
    await ref.read(kprProvider.notifier).loadAll();
  }

  Future<bool> _confirmDelete(KPRSimulation sim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Simulation'),
        content: Text(
          'Delete "${sim.name.isEmpty ? 'this simulation' : sim.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(kprProvider.notifier).delete(sim.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Simulation deleted' : 'Failed to delete simulation'),
          ),
        );
      }
      return success;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kprProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mortgage (KPR)'),
      ),
      body: state.isLoading && state.simulations.isEmpty
          ? const LoadingIndicator()
          : state.error != null && state.simulations.isEmpty
              ? ErrorDisplay(
                  message: state.error!,
                  onRetry: _onRefresh,
                )
              : RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: state.simulations.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.6,
                              child: _buildEmptyState(isDark),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: state.simulations.length,
                          itemBuilder: (_, i) =>
                              _buildSimulationCard(state.simulations[i], isDark),
                        ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/debt/kpr/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.home_outlined,
            size: 64,
            color: AppColors.textSecondary.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            'No mortgage simulations yet',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create your first KPR simulation',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationCard(KPRSimulation sim, bool isDark) {
    final monthlyPayment = sim.summary?['monthly_payment'] as int?;
    final totalInterest = sim.summary?['total_interest'] as int?;
    final monthlyPaymentStr = monthlyPayment != null
        ? formatCurrency(monthlyPayment)
        : _estimateMonthlyPayment(sim.totalLoan, sim.tenorMonths);
    final totalInterestStr = totalInterest != null
        ? formatCurrency(totalInterest)
        : formatCurrency(0);

    return Dismissible(
      key: ValueKey(sim.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.highlight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) => _confirmDelete(sim),
      child: GestureDetector(
        onTap: () => context.go('/debt/kpr/${sim.id}'),
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.home_work_outlined,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sim.name.isNotEmpty ? sim.name : 'KPR Simulation',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _tenorLabel(sim.tenorMonths),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildInterestBadge(sim.interestType),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _infoColumn(
                        'Property Price',
                        formatCurrency(sim.propertyPrice),
                      ),
                    ),
                    Expanded(
                      child: _infoColumn(
                        'Loan Amount',
                        formatCurrency(sim.totalLoan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _infoColumn(
                        'Monthly Payment',
                        monthlyPaymentStr,
                      ),
                    ),
                    Expanded(
                      child: _infoColumn(
                        'Total Interest',
                        totalInterestStr,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterestBadge(String interestType) {
    final label = interestType[0].toUpperCase() + interestType.substring(1);
    Color bgColor;
    Color textColor;
    switch (interestType.toLowerCase()) {
      case 'fixed':
        bgColor = AppColors.success.withAlpha(30);
        textColor = AppColors.success;
        break;
      case 'floating':
        bgColor = AppColors.warning.withAlpha(30);
        textColor = AppColors.warning;
        break;
      case 'graduated':
        bgColor = AppColors.accent.withAlpha(30);
        textColor = AppColors.accent;
        break;
      case 'mix':
        bgColor = AppColors.highlight.withAlpha(30);
        textColor = AppColors.highlight;
        break;
      default:
        bgColor = AppColors.textSecondary.withAlpha(30);
        textColor = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _tenorLabel(int months) {
    if (months < 12) return '$months months';
    final years = months ~/ 12;
    final rem = months % 12;
    if (rem == 0) return '$years years';
    return '$years years $rem months';
  }

  String _estimateMonthlyPayment(int totalLoan, int tenorMonths) {
    if (totalLoan <= 0 || tenorMonths <= 0) return formatCurrency(0);
    // Rough estimate assuming ~9% annual interest
    const annualRate = 0.09;
    final monthlyRate = annualRate / 12;
    final factor = pow(1 + monthlyRate, tenorMonths);
    final payment =
        (totalLoan * monthlyRate * factor) / (factor - 1);
    return formatCurrency(payment.round());
  }
}
