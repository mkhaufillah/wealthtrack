import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/credit_card_provider.dart';
import '../../models/credit_card_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../features/home/providers/dashboard_provider.dart';
import '../../../../core/theme/app_theme.dart';

class CreditCardDetailScreen extends ConsumerStatefulWidget {
  final int cardId;
  const CreditCardDetailScreen({super.key, required this.cardId});

  @override
  ConsumerState<CreditCardDetailScreen> createState() => _CreditCardDetailScreenState();
}

class _CreditCardDetailScreenState extends ConsumerState<CreditCardDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    Future.microtask(() {
      ref.read(creditCardProvider.notifier).loadCardDetail(widget.cardId);
      ref.read(creditCardProvider.notifier).loadProjection();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(creditCardProvider.notifier).loadCardDetail(widget.cardId);
    await ref.read(creditCardProvider.notifier).loadProjection();
  }

  Future<bool> _confirmDeleteCard(CreditCardModel card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Credit Card'),
        content: Text(
          'Delete "${card.name}"? This will also remove all transactions and installments.',
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
      final success = await ref.read(creditCardProvider.notifier).deleteCard(card.id);
      if (mounted && success) {
        context.pop();
      }
      return success;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(creditCardProvider);
    final card = state.selectedCard;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<int>(homeRefreshProvider, (prev, next) {
      if (prev != next) {
        try {
          ref.read(creditCardProvider.notifier).loadCardDetail(widget.cardId);
        } catch (_) {}
        ref.read(creditCardProvider.notifier).loadProjection();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(card?.name ?? 'Credit Card'),
        scrolledUnderElevation: 0,
        actions: [
          if (card != null)
            IconButton(
              onPressed: () => _confirmDeleteCard(card),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
        bottom: card != null
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Transactions'),
                  Tab(text: 'Installments'),
                ],
              )
            : null,
      ),
      floatingActionButton: card != null
          ? FloatingActionButton(
              onPressed: () {
                if (_tabController.index == 0) {
                  _addTransaction();
                } else {
                  context.push('/debt/credit-cards/${card.id}/installments/new');
                }
              },
              child: Icon(
                _tabController.index == 0
                    ? Icons.add_shopping_cart
                    : Icons.add,
              ),
            )
          : null,
      body: state.isLoading && card == null
          ? const LoadingIndicator()
          : state.error != null && card == null
              ? ErrorDisplay(
                  message: state.error!,
                  onRetry: _onRefresh,
                )
              : card == null
                  ? ErrorDisplay(
                      message: 'Card not found',
                      onRetry: _onRefresh,
                    )
                  : Column(
                      children: [
                        _buildCardInfoHeader(card, isDark),
                        if (state.projection != null)
                          _buildProjectionSummary(
                            state.projection!.perCard
                                .where((p) => p['card_id'] == card?.id)
                                .firstOrNull,
                            state.projection!,
                            isDark,
                            card: card,
                          ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              RefreshIndicator(
                                onRefresh: _onRefresh,
                                child: _buildTransactionsTab(card),
                              ),
                              RefreshIndicator(
                                onRefresh: _onRefresh,
                                child: _buildInstallmentsTab(card),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildCardInfoHeader(CreditCardModel card, bool isDark) {
    final maskedNumber = card.cardNumberLast4.isNotEmpty
        ? '**** **** **** ${card.cardNumberLast4}'
        : null;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkCard]
              : [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (maskedNumber != null) ...[
            Text(
              maskedNumber,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextPrimary : Colors.white70,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _headerInfoItem(
                  'Billing Date',
                  _ordinalSuffix(card.billingDate),
                  Icons.calendar_today,
                  isDark,
                ),
              ),
              Expanded(
                child: _headerInfoItem(
                  'Due Date',
                  _ordinalSuffix(card.dueDate),
                  Icons.event,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _headerInfoItem(
                  'Credit Limit',
                  formatCurrency(card.creditLimit),
                  Icons.credit_card,
                  isDark,
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerInfoItem(String label, String value, IconData icon, bool isDark) {
    final textColor = isDark ? AppColors.darkTextPrimary : Colors.white;
    final subTextColor = isDark ? AppColors.darkTextSecondary : Colors.white70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: subTextColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: subTextColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectionSummary(Map<String, dynamic>? cardProjection, NextMonthProjection projection, bool isDark, {CreditCardModel? card}) {
    final totalForCard = cardProjection?['total'] as int? ?? projection.totalExpected;
    final perCardCount = card?.installments
            ?.where((inst) => inst.remainingMonths > 0)
            .length ??
        projection.totalInstallments;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up, size: 20, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Month Projection',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${perCardCount} installments · ${formatCurrency(totalForCard)} expected',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(CreditCardModel card) {
    final transactions = card.transactions ?? [];

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: 12),
            Text(
              'No transactions yet',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: transactions.length,
      itemBuilder: (_, i) => _buildTransactionItem(transactions[i]),
    );
  }

  Widget _buildTransactionItem(CCTransaction tx) {
    final dateStr = tx.transactionDate.isNotEmpty
        ? _formatDate(tx.transactionDate)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tx.isInstallment
                  ? AppColors.accent.withAlpha(25)
                  : AppColors.highlight.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              tx.isInstallment ? Icons.repeat : Icons.receipt,
              size: 18,
              color: tx.isInstallment ? AppColors.accent : AppColors.highlight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description.isNotEmpty ? tx.description : 'Transaction',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatCurrency(tx.amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.highlight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentsTab(CreditCardModel card) {
    final installments = card.installments ?? [];

    if (installments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat_outlined,
              size: 48,
              color: AppColors.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: 12),
            Text(
              'No installments yet',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: installments.length,
      itemBuilder: (_, i) => _buildInstallmentItem(installments[i]),
    );
  }

  Widget _buildInstallmentItem(CCInstallment inst) {
    final progress = inst.totalMonths - inst.remainingMonths;
    final progressRatio = inst.totalMonths > 0
        ? progress / inst.totalMonths
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inst.description.isNotEmpty ? inst.description : 'Installment',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio.clamp(0.0, 1.0),
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                inst.remainingMonths == 0 ? AppColors.success : AppColors.accent,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progress / ${inst.totalMonths} months',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _infoColumn('Monthly', formatCurrency(inst.monthlyAmount)),
              ),
              Expanded(
                child: _infoColumn('Total', formatCurrency(inst.totalAmount)),
              ),
            ],
          ),
        ],
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
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
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

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  void _addTransaction() {
    final descriptionCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final amountFocusNode = FocusNode();
    bool amountFocused = false;
    DateTime selectedDate = DateTime.now();

    void formatAmountOnFocusChange(bool isFocused) {
      if (isFocused) {
        final raw = amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
        if (raw != amountCtrl.text) {
          amountCtrl.value = TextEditingValue(
            text: raw,
            selection: TextSelection.collapsed(offset: raw.length),
          );
        }
      } else {
        final digits = amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
        if (digits.isNotEmpty) {
          final buf = StringBuffer();
          int count = 0;
          for (int i = digits.length - 1; i >= 0; i--) {
            if (count > 0 && count % 3 == 0) buf.write('.');
            buf.write(digits[i]);
            count++;
          }
          final formatted = 'Rp ${buf.toString().split('').reversed.join('')}';
          amountCtrl.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
      }
    }

    amountFocusNode.addListener(() {
      amountFocused = amountFocusNode.hasFocus;
      formatAmountOnFocusChange(amountFocused);
    });

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Add Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Groceries',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                focusNode: amountFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(selectedDate),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final desc = descriptionCtrl.text.trim();
                final amount = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^\d]'), ''));
                if (desc.isEmpty || amount == null || amount <= 0) return;

                final success = await ref.read(creditCardProvider.notifier).addTransaction(
                  widget.cardId,
                  {
                    'description': desc,
                    'amount': amount,
                    'transaction_date': DateFormat('yyyy-MM-dd').format(selectedDate),
                  },
                );

                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Transaction added' : 'Failed to add transaction'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
