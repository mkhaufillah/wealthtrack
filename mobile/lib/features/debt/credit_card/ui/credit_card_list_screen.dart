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
          'Hapus "${card.name.isEmpty ? 'kartu ini' : card.name}"? Gak bisa dibalikin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(creditCardProvider.notifier).deleteCard(card.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Kartu kredit kehapus' : 'Gagal hapus kartu kredit'),
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
                              return _buildSummaryHeader(totalLimit, totalActiveInstallments);
                            }
                            return _buildCard(state.cards[i - 1]);
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/debt/credit-cards/new'),
        child: AppIcon(AppIcons.add),
      ),
    );
  }

  Widget _buildSummaryHeader(int totalLimit, int totalActiveInstallments) {
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
            'Summary',
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
                child: _summaryItem('Total limit', formatCurrency(totalLimit), Icons.credit_card_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryItem('Cicilan aktif', totalActiveInstallments.toString(), Icons.receipt_long_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accent),
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
          Icon(
            Icons.credit_card_outlined,
            size: 64,
            color: AppColors.textSecondary.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada kartu kredit',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + buat nambah kartu kredit',
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
        : 'Gak ada nomor';
    final dueDateLabel = 'Jatuh tempo ${_ordinalSuffix(card.dueDate)}';
    final billingDateLabel = 'Tagihan ${_ordinalSuffix(card.billingDate)}';

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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.credit_card,
                        size: 22,
                        color: AppColors.accent,
                      ),
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
                                  card.name.isNotEmpty ? card.name : 'Kartu kredit',
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
                                      '🏠 Member',
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
                        'Jatuh tempo',
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
                        'Tanggal tagihan',
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
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }
}
