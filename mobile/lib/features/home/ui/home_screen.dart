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
import '../../../shared/providers/app_providers.dart';
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
  int _savingsBalance = 0;
  int _emergencyBalance = 0;
  Map<String, dynamic> _debtData = {};
  bool _debtLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).load());
    Future.microtask(() => _loadAllTimeBalances());
    Future.microtask(() => ref.read(ocrPendingCountProvider.notifier).load());
    Future.microtask(() => _loadDebtSummary());
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
    } catch (e) {
      debugPrint('ERROR: $e');
    }
  }

  Future<void> _loadDebtSummary() async {
    try {
      final api = ref.read(apiClientProvider);
      late Map<String, dynamic> data;
      try {
        final resp = await api.get('/summaries/debt/household');
        data = resp.data as Map<String, dynamic>? ?? {};
      } catch (_) {
        final resp = await api.get('/summaries/debt');
        data = resp.data as Map<String, dynamic>? ?? {};
      }
      if (mounted) {
        setState(() {
          _debtData = data;
          _debtLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ERROR: $e');
      if (mounted) setState(() => _debtLoading = false);
    }
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
        _loadDebtSummary();
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
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: ShimmerLoading(itemCount: 5, itemHeight: 96),
              )
            : state.error != null
                ? ErrorDisplay(
                    message: state.error!,
                    onRetry: () => ref.read(dashboardProvider.notifier).load(),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(dashboardProvider.notifier).load(force: true);
                      _loadDebtSummary();
                      _loadAllTimeBalances();
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                      children: [
                        _HiRow(name: firstName),
                        const SizedBox(height: 14),
                        BalanceCard(
                          balance: state.balance,
                          income: state.totalIncome,
                          expense: state.totalExpense,
                          cycleLabel: t('home.hero_title'),
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
                          savings: _savingsBalance,
                          emergency: _emergencyBalance,
                        ),
                        if (!_debtLoading &&
                            _debtData['total_debt'] != null &&
                            (_debtData['total_debt'] as int) > 0) ...[
                          const SizedBox(height: 10),
                          _DebtStrip(
                            total: _debtData['total_debt'] as int,
                            members: _memberCount(),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _QuickList(
                          savings: _savingsBalance,
                          emergency: _emergencyBalance,
                        ),
                        const SizedBox(height: 22),
                        _RecentSection(transactions: state.recentTransactions),
                      ],
                    ),
                  ),
      ),
    );
  }

  int _memberCount() {
    final members = _debtData['members'] as List<dynamic>?;
    return members?.length ?? 1;
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
  const _HiRow({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hai, $name',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Saldo kamu, sepanjang waktu',
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
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
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
            label: 'Tabungan',
            value: formatCurrency(savings),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PocketCard(
            icon: AppIcons.shield,
            iconBg: AppColors.mint,
            label: 'Dana darurat',
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppIcon(icon, size: 20, color: AppColors.textPrimary),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.highlight.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppIcon(AppIcons.home, size: 20, color: AppColors.highlight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Utang berjalan',
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
                color: AppColors.accent.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$members orang',
                style: TextStyle(fontSize: 11, color: AppColors.accent),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppIcon(icon, size: 22, color: AppColors.textPrimary),
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
              'Baru saja',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/transactions'),
              child: Text(
                'Lihat semua',
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
              'Belum ada transaksi',
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
