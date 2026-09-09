import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kpr_provider.dart';
import '../../models/kpr_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/providers/auth_provider.dart';

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

  // ── Helpers ──────────────────────────────────────

  Future<bool> _confirmDelete(KPRSimulation sim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('kpr.delete')),
        content: Text(
          t('kpr.delete_confirm').replaceAll('{label}', sim.name.isEmpty ? t('kpr.this_sim') : sim.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('common.delete'), style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(kprProvider.notifier).delete(sim.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? t('kpr.sim_deleted') : t('kpr.sim_delete_fail')),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('kpr.title')),
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
                              child: _buildEmptyState(),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: state.simulations.length,
                          itemBuilder: (_, i) =>
                              _buildSimulationCard(state.simulations[i]),
                        ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/debt/kpr/new'),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        child: AppIcon(AppIcons.add, color: AppColors.onAccent),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.house, size: 64, color: AppColors.textSecondary.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            t('kpr.empty'),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('kpr.empty_add'),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationCard(KPRSimulation sim) {
    final monthlyPayment = sim.monthlyPayment;
    final totalInterest = sim.totalInterest;
    final monthlyPaymentStr = formatCurrency(monthlyPayment);
    final totalInterestStr = totalInterest > 0
        ? formatCurrency(totalInterest)
        : formatCurrency(0);

    // Current month info
    final monthsElapsed = _monthsBetween(sim.startMonth, sim.startYear);
    final actualMonth = monthsElapsed.clamp(1, sim.tenorMonths);

    // Owner badge check
    final currentUser = ref.read(authProvider).user;
    final isNotOwner = currentUser != null && sim.userId != currentUser.id;

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
        child: AppIcon(AppIcons.trash, color: AppColors.surface, size: 28),
      ),
      confirmDismiss: (_) => _confirmDelete(sim),
      child: GestureDetector(
        onTap: () => context.push('/debt/kpr/${sim.id}'),
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
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AppIcon(AppIcons.house, size: 16, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sim.name.isNotEmpty ? sim.name : t('kpr.title'),
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
                          if (isNotOwner) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                t('hh.member_badge'),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.warning),
                              ),
                            ),
                          ],
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
                        t('kpr.house_price'),
                        formatCurrency(sim.propertyPrice),
                      ),
                    ),
                    Expanded(
                      child: _infoColumn(
                        t('kpr.loan'),
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
                        t('kpr.installment'),
                        monthlyPaymentStr,
                      ),
                    ),
                    Expanded(
                      child: _infoColumn(
                        t('kpr.total_interest'),
                        totalInterestStr,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Current month info row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accent.withAlpha(40)),
                  ),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.calendar, size: 14, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t('kpr.due_label')
                              .replaceAll('{month}', '$actualMonth')
                              .replaceAll('{total}', '${sim.tenorMonths}')
                              .replaceAll('{amount}', formatCurrency(sim.currentMonthPayment > 0 ? sim.currentMonthPayment : monthlyPayment)),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterestBadge(String interestType) {
    final label = kprInterestLabel(interestType);
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
    if (months < 12) return t('kpr.month_n').replaceAll('{n}', '$months');
    final years = months ~/ 12;
    final remaining = months % 12;
    if (remaining == 0) return t('common.year_n').replaceAll('{n}', '$years');
    return t('kpr.years_months').replaceAll('{y}', '$years').replaceAll('{m}', '$remaining');
  }

  int _monthsBetween(int startMonth, int startYear) {
    final now = DateTime.now();
    return (now.year - startYear) * 12 + (now.month - startMonth) + 1;
  }
}
