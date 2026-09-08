import 'package:flutter/material.dart';
import '../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/dashboard_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../auth/providers/auth_provider.dart';
import '../../ocr/providers/ocr_provider.dart';
import '../../transactions/models/transaction_model.dart';
import '../../transactions/ui/widgets/transaction_tile.dart';
import 'widgets/balance_card.dart';

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
    Future.microtask(() => ref.read(ocrPendingCountProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final ocrState = ref.watch(ocrPendingCountProvider);
    final user = ref.watch(authProvider).user;
    final firstName = (user?.displayName.isNotEmpty ?? false)
        ? user!.displayName.split(' ').first
        : 'Kamu';

    ref.listen<int>(homeRefreshProvider, (prev, next) {
      if (prev != next) {
        ref.read(dashboardProvider.notifier).load(force: true);
      }
    });

    ref.listen<OcrState>(ocrPendingCountProvider, (previous, next) {
      if (previous != null && next.pendingCount < previous.pendingCount) {
        ref.read(dashboardProvider.notifier).load(force: true);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: state.isLoading
            ? const HomeSkeleton()
            : state.error != null
                ? ErrorDisplay(
                    message: state.error!,
                    onRetry: () => ref.read(dashboardProvider.notifier).load(),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(dashboardProvider.notifier).load(force: true);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                      children: [
                        _HiRow(
                          name: firstName,
                          fullName: user?.displayName ?? firstName,
                        ),
                        const SizedBox(height: 14),
                        BalanceCard(
                          balance: state.balance,
                          income: state.totalIncome,
                          expense: state.totalExpense,
                          cycleLabel: t('home.hero_title'),
                          amountText: state.balanceDisplay,
                        ),
                        if (ocrState.pendingCount > 0) ...[
                          const SizedBox(height: 10),
                          _ocrBanner(ocrState.pendingCount),
                        ],
                        if (ocrState.hasFailure) ...[
                          const SizedBox(height: 10),
                          _ocrError(ocrState),
                        ],
                        const SizedBox(height: 10),
                        _PocketRow(
                          savings: state.savings,
                          emergency: state.emergency,
                        ),
                        if (state.debtVisible && state.debtTotal > 0) ...[
                          const SizedBox(height: 10),
                          _DebtStrip(
                            total: state.debtTotal,
                            members: 1,
                          ),
                        ],
                        const SizedBox(height: 10),
                        _QuickList(
                          savings: state.savings,
                          emergency: state.emergency,
                        ),
                        const SizedBox(height: 22),
                        _RecentSection(transactions: state.recentTransactions),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _ocrBanner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '$count transaksi sedang diproses…',
            style: TextStyle(fontSize: 13, color: AppColors.warning),
          ),
        ],
      ),
    );
  }

  Widget _ocrError(OcrState ocrState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.highlight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.alert, size: 16, color: AppColors.highlight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ocrState.error ?? 'OCR gagal diproses',
              style: TextStyle(fontSize: 13, color: AppColors.highlight),
            ),
          ),
          GestureDetector(
            onTap: () => ref.read(ocrPendingCountProvider.notifier).dismissError(),
            child: AppIcon(AppIcons.close, size: 16, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HiRow extends StatelessWidget {
  final String name;
  final String fullName;
  const _HiRow({required this.name, required this.fullName});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t('home.greeting')}, $name',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t('home.greeting_sub'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.avatarBackground(fullName),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.avatarText(fullName),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PocketRow extends StatelessWidget {
  final int savings;
  final int emergency;
  const _PocketRow({required this.savings, required this.emergency});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PocketCard(
            icon: AppIcons.piggy,
            iconBg: AppColors.butter,
            label: t('home.savings_pocket'),
            value: formatCurrency(savings),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PocketCard(
            icon: AppIcons.shield,
            iconBg: AppColors.mint,
            label: t('home.emergency_pocket'),
            value: formatCurrency(emergency),
          ),
        ),
      ],
    );
  }
}

class _PocketCard extends StatelessWidget {
  final List<List<dynamic>> icon;
  final Color iconBg;
  final String label;
  final String value;
  const _PocketCard({
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: AppIcon(icon, size: 16, color: AppColors.onAccent),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtStrip extends StatelessWidget {
  final int total;
  final int members;
  const _DebtStrip({required this.total, required this.members});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.highlight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.highlight.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AppIcon(AppIcons.home, size: 16, color: AppColors.highlight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('home.debt_running'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  formatCurrency(total),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.highlight,
                  ),
                ),
              ],
            ),
          ),
          if (members > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.highlight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$members orang',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.onAccent),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickList extends StatelessWidget {
  final int savings;
  final int emergency;
  const _QuickList({required this.savings, required this.emergency});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          _QuickItem(
            iconBg: AppColors.secondary,
            icon: AppIcons.ai,
            title: t('home.ai'),
            subtitle: t('home.ai_sub'),
            onTap: () => context.push('/ai/advise'),
          ),
          Divider(height: 1, color: AppColors.divider),
          _QuickItem(
            iconBg: AppColors.mint,
            icon: AppIcons.bank,
            title: t('home.debt_hub'),
            subtitle: t('home.debt_hub_sub'),
            onTap: () => context.push('/debt'),
          ),
        ],
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  final Color iconBg;
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickItem({
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppIcon(icon, size: 16, color: AppColors.onAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(AppIcons.next, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  final List<TransactionModel> transactions;
  const _RecentSection({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t('home.recent'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/transactions'),
              child: Text(
                t('home.see_all'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (transactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              t('home.empty_tx_short'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                for (var i = 0; i < transactions.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  TransactionTile(transaction: transactions[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
