import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/ocr/providers/ocr_provider.dart';
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
  Map<String, dynamic> _debtData = {};
  bool _debtLoading = true;

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd MMM').format(dt);
    } catch (e) {
      debugPrint('ERROR: $e');
      return iso;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).load());
    Future.microtask(() => _loadAllTimeBalances());
    Future.microtask(() => ref.read(ocrPendingCountProvider.notifier).load());
    Future.microtask(() => _loadDebtSummary());
  }

  @override
  void dispose() {
    super.dispose();
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
      // Silently fail — the summary card is optional
    }
  }

  Future<void> _loadDebtSummary() async {
    try {
      final api = ref.read(apiClientProvider);
      // Try household endpoint first — shows aggregated family debt
      late Map<String, dynamic> data;
      try {
        final resp = await api.get('/summaries/debt/household');
        data = resp.data as Map<String, dynamic>? ?? {};
      } catch (_) {
        // Fall back to personal debt summary
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

    // Reload dashboard when homeRefreshProvider is incremented
    ref.listen<int>(homeRefreshProvider, (prev, next) {
      if (prev != next) {
        ref.read(dashboardProvider.notifier).load(force: true);
        _loadDebtSummary();
      }
    });

    // Auto-refresh when OCR pending drops to 0
    ref.listen<OcrState>(ocrPendingCountProvider, (previous, next) {
      if (previous != null && next.pendingCount < previous.pendingCount) {
        ref.read(dashboardProvider.notifier).load(force: true);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('WealthTrack')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(dashboardProvider.notifier).load(force: true);
          _loadDebtSummary();
        },
        child: state.isLoading
            ? const ShimmerLoading(itemCount: 4, itemHeight: 120)
            : state.error != null
                ? ErrorDisplay(message: state.error!, onRetry: () => ref.read(dashboardProvider.notifier).load())
                : ListView(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                    children: [
                      // OCR processing banner
                      if (ocrState.pendingCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ocrState.pendingCount == 1
                                      ? '⏳ 1 transaction being processed...'
                                      : '⏳ ${ocrState.pendingCount} transactions being processed...',
                                  style: TextStyle(fontSize: 13, color: AppColors.warning),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // OCR error banner
                      if (ocrState.hasFailure)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.highlight.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                 Icon(Icons.error_outline, size: 16, color: AppColors.highlight),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ocrState.error ?? 'OCR processing failed',
                                    style: TextStyle(fontSize: 13, color: AppColors.highlight),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => ref.read(ocrPendingCountProvider.notifier).dismissError(),
                                  child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      BalanceCard(
                        balance: state.balance,
                        income: state.totalIncome,
                        expense: state.totalExpense,
                        cycleLabel: state.dateFrom != null && state.dateTo != null
                            ? '${_formatDate(state.dateFrom!)} – ${_formatDate(state.dateTo!)}'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildCategoriesCard(),
                      if (!_debtLoading && _debtData['total_debt'] != null && (_debtData['total_debt'] as int) > 0)
                        ...[
                          const SizedBox(height: 8),
                          _buildDebtSummaryCard(),
                        ],
                      const SizedBox(height: 8),
                      _buildAiCard(),
                      const SizedBox(height: 8),
                      _buildDebtCard(),
                      const SizedBox(height: 24),
                      RecentTransactions(transactions: state.recentTransactions),
                    ],
                  ),
      ),
    );
  }
  Widget _buildDebtSummaryCard() {
    final totalDebt = _debtData['total_debt'] as int? ?? 0;
    final members = _debtData['members'] as List<dynamic>?;
    final isHousehold = members != null && members.length > 1;

    // Filter members with visible debt from current user's perspective
    final visibleMembers = <Map<String, dynamic>>[];
    if (members != null) {
      for (final m in members) {
        final mData = m as Map<String, dynamic>;
        final isCurrentUser = mData['is_current_user'] as bool? ?? false;
        final kprPrivate = mData['kpr_private'] as int? ?? 0;
        final kprShared = mData['kpr_shared'] as int? ?? 0;
        final ccPrivate = mData['cc_private'] as int? ?? 0;
        final ccShared = mData['cc_shared'] as int? ?? 0;

        final visibleTotal = isCurrentUser
            ? (kprPrivate + kprShared + ccPrivate + ccShared)
            : (kprShared + ccShared);

        if (visibleTotal > 0) {
          mData['_visible_total'] = visibleTotal;
          visibleMembers.add(mData);
        }
      }
    }

    return Card(
      color: AppColors.highlight.withAlpha(15),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.highlight.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.highlight.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: AppColors.highlight, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Total Outstanding Debt',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (isHousehold)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${members!.length} members',
                      style: TextStyle(fontSize: 11, color: AppColors.accent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Per-member breakdown
            if (visibleMembers.isNotEmpty)
              ..._buildMemberSections(visibleMembers),

            // Total
            Padding(
              padding: EdgeInsets.only(top: visibleMembers.isNotEmpty ? 10 : 0),
              child: Column(
                children: [
                  Divider(height: 24, color: AppColors.divider),
                  const SizedBox(height: 10),
                  _debtRow('Total', formatCurrency(totalDebt),
                      valueColor: AppColors.highlight, bold: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMemberSections(List<Map<String, dynamic>> members) {
    final sections = <Widget>[];
    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      final name = m['display_name'] as String? ?? '';
      final isCurrentUser = m['is_current_user'] as bool? ?? false;
      final memberTotal = m['_visible_total'] as int? ?? 0;
      final kprPrivate = m['kpr_private'] as int? ?? 0;
      final kprShared = m['kpr_shared'] as int? ?? 0;
      final ccPrivate = m['cc_private'] as int? ?? 0;
      final ccShared = m['cc_shared'] as int? ?? 0;

      sections.add(_buildMemberSection(
        name: name,
        total: memberTotal,
        isCurrentUser: isCurrentUser,
        kprPrivate: kprPrivate,
        kprShared: kprShared,
        ccPrivate: ccPrivate,
        ccShared: ccShared,
        showDivider: i < members.length - 1,
      ));
    }
    return sections;
  }

  Widget _buildMemberSection({
    required String name,
    required int total,
    required bool isCurrentUser,
    required int kprPrivate,
    required int kprShared,
    required int ccPrivate,
    required int ccShared,
    bool showDivider = false,
  }) {
    final items = <Widget>[
      // Member name + total
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: AppColors.accent.withAlpha(30),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text(
              formatCurrency(total),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.highlight),
            ),
          ],
        ),
      ),
      // Member separator
      Divider(height: 24, color: AppColors.divider),
    ];

    // Private debts (current user only)
    if (isCurrentUser && kprPrivate > 0) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _debtRow('KPR - private', formatCurrency(kprPrivate)),
      ));
    }
    if (isCurrentUser && ccPrivate > 0) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _debtRow('Credit - private', formatCurrency(ccPrivate)),
      ));
    }

    // Shared debts (visible to current user from any member)
    if (kprShared > 0) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _debtRow('KPR - shared', formatCurrency(kprShared)),
      ));
    }
    if (ccShared > 0) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _debtRow('Credit - shared', formatCurrency(ccShared)),
      ));
    }

    if (showDivider) {
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 0),
        child: Divider(height: 24, color: AppColors.divider),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items,
    );
  }

  Widget _debtRow(String label, String value, {Color? valueColor, bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
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

  Widget _buildDebtCard() {
    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/debt'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.highlight.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_outlined,
                    color: AppColors.textPrimary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Debt Tracker',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Manage KPR, credit cards & installments',
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