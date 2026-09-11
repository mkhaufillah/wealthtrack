import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/credit_card_provider.dart';
import '../../models/credit_card_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/providers/auth_provider.dart';

class CreditCardListScreen extends ConsumerStatefulWidget {
  const CreditCardListScreen({super.key});

  @override
  ConsumerState<CreditCardListScreen> createState() => _CreditCardListScreenState();
}

class _CreditCardListScreenState extends ConsumerState<CreditCardListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(creditCardProvider.notifier).loadCards());
  }

  Future<void> _onRefresh() async {
    await ref.read(creditCardProvider.notifier).loadCards();
  }

  Future<bool> _confirmDelete(CreditCardModel card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('cc.delete')),
        content: Text(
          t('cc.delete_confirm_body').replaceAll('{label}', card.name.isEmpty ? t('cc.this_card') : card.name),
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
      final success = await ref.read(creditCardProvider.notifier).deleteCard(card.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? t('cc.card_deleted') : t('cc.card_delete_fail')),
          ),
        );
      }
      return success;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(creditCardProvider);

    // Compute summary values
    final totalLimit = state.cards.fold<int>(0, (sum, c) => sum + c.creditLimit);
    final totalActiveInstallments = state.cards.fold<int>(0, (sum, c) {
      return sum + (c.activeInstallments);
    });
    final totalActiveTransactions = state.cards.fold<int>(0, (sum, c) {
      return sum + (c.activeTransactions);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('cc.title')),
      ),
      body: state.isLoading && state.cards.isEmpty
          ? const LoadingIndicator()
          : state.error != null && state.cards.isEmpty
              ? ErrorDisplay(
                  message: state.error!,
                  onRetry: _onRefresh,
                )
              : RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: state.cards.isEmpty
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
                          itemCount: state.cards.length + 1, // +1 for summary header
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return _buildSummaryHeader(
                                totalLimit,
                                totalActiveInstallments,
                                totalActiveTransactions,
                              );
                            }
                            return _buildCard(state.cards[i - 1]);
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/debt/credit-cards/new'),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        child: AppIcon(AppIcons.add, color: AppColors.onAccent),
      ),
    );
  }

  Widget _buildSummaryHeader(
    int totalLimit,
    int totalActiveInstallments,
    int totalActiveTransactions,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('cc.summary'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryItem(t('cc.total_limit'), formatCurrency(totalLimit), AppIcons.card),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryItem(t('cc.inst_active'), totalActiveInstallments.toString(), AppIcons.receipt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryItem(t('cc.txn_active'), totalActiveTransactions.toString(), AppIcons.receipt),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, List<List<dynamic>> icon) {
    return Row(
      children: [
        AppIcon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.card, size: 64, color: AppColors.textSecondary.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            t('cc.empty'),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('cc.empty_add'),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(CreditCardModel card) {
    final maskedNumber = card.cardNumberLast4.isNotEmpty
        ? '**** **** **** ${card.cardNumberLast4}'
        : t('cc.no_number');
    final dueDateLabel = '${t('cc.due_label')} ${_ordinalSuffix(card.dueDate)}';
    final billingDateLabel = t('cc.bill_on').replaceAll('{n}', '${card.billingDate}');

    // Owner badge check
    final currentUser = ref.read(authProvider).user;
    final isNotOwner = currentUser != null && card.userId != currentUser.id;

    return Dismissible(
      key: ValueKey(card.id),
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
      confirmDismiss: (_) => _confirmDelete(card),
      child: GestureDetector(
        onTap: () => context.push('/debt/credit-cards/${card.id}'),
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
                      child: AppIcon(AppIcons.card, size: 16, color: AppColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  card.name.isNotEmpty ? card.name : t('cc.title'),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isNotOwner)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
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
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            maskedNumber,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _infoColumn(
                        'Limit',
                        formatCurrency(card.creditLimit),
                      ),
                    ),
                    Expanded(
                      child: _infoColumn(
                        t('cc.due_label'),
                        dueDateLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _infoColumn(
                        t('cc.bill_label'),
                        billingDateLabel,
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  String _ordinalSuffix(int day) {
    return t('cc.day_n').replaceAll('{n}', '$day');
  }
}
