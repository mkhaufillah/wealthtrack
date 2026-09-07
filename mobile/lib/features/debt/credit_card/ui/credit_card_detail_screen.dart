import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/credit_card_provider.dart';
import '../../models/credit_card_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';
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
        title: Text(t('cc.delete')),
        content: Text(
          'Hapus "${card.name}"? Transaksi dan cicilannya ikut kehapus.',
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
      if (mounted && success) {
        context.pop();
      }
      return success;
    }
    return false;
  }

  Future<bool> _confirmDeleteTxn(CCTransaction tx) async {
    final label = tx.description.isNotEmpty ? tx.description : 'Transaksi';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('cc.del_txn')),
        content: Text(t('cc.delete_confirm_body').replaceAll('{label}', label)),
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
      final ok = await ref.read(creditCardProvider.notifier).deleteTransaction(widget.cardId, tx.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? t('cc.txn_gone') : t('tx.del_fail'))),
        );
      }
      return ok;
    }
    return false;
  }

  Future<bool> _confirmDeleteInst(CCInstallment inst) async {
    final label = inst.description.isNotEmpty ? inst.description : 'Cicilan';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('cc.del_inst')),
        content: Text(t('cc.delete_confirm_body').replaceAll('{label}', label)),
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
      final ok = await ref.read(creditCardProvider.notifier).deleteInstallment(widget.cardId, inst.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? t('cc.inst_gone') : t('tx.del_fail'))),
        );
      }
      return ok;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(creditCardProvider);
    final card = state.selectedCard;

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
        title: Text(card?.name ?? 'Kartu kredit'),
        scrolledUnderElevation: 0,
        actions: [
          if (card != null)
            IconButton(
              onPressed: () => _confirmDeleteCard(card),
              icon: AppIcon(AppIcons.trash),
            ),
        ],
        bottom: card != null
            ? TabBar(
                controller: _tabController,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textPrimary.withOpacity(0.6),
                indicatorColor: AppColors.textPrimary,
                indicatorWeight: 2,
                dividerColor: AppColors.divider,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: [
                  Tab(text: t('cc.tab_txn')),
                  Tab(text: t('cc.tab_inst')),
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
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              child: AppIcon(AppIcons.add, color: AppColors.onAccent),
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
                      message: t('cc.not_found'),
                      onRetry: _onRefresh,
                    )
                  : Column(
                      children: [
                        _buildCardInfoHeader(card),
                        if (state.projection != null)
                          _buildProjectionSummary(
                            state.projection!.perCard
                                .where((p) => p['card_id'] == card?.id)
                                .firstOrNull,
                            state.projection!,
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

  Widget _buildCardInfoHeader(CreditCardModel card) {
    final maskedNumber = card.cardNumberLast4.isNotEmpty
        ? '**** **** **** ${card.cardNumberLast4}'
        : null;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.creditCardGradient,
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
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _headerInfoItem('Tanggal tagihan', _ordinalSuffix(card.billingDate), AppIcons.calendar),
              ),
              Expanded(
                child: _headerInfoItem('Jatuh tempo', _ordinalSuffix(card.dueDate), AppIcons.clock),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _headerInfoItem('Limit', formatCurrency(card.creditLimit), AppIcons.card),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerInfoItem(String label, String value, List<List<dynamic>> icon) {
    final textColor = AppColors.textPrimary;
    final subTextColor = AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(icon, size: 14, color: subTextColor),
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

  Widget _buildProjectionSummary(Map<String, dynamic>? cardProjection, NextMonthProjection projection, {CreditCardModel? card}) {
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
          AppIcon(AppIcons.chartUp, size: 20, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('cc.proj_next'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$perCardCount cicilan · ${formatCurrency(totalForCard)} perkiraan',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
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
            AppIcon(
              AppIcons.receipt,
              size: 48,
              color: AppColors.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: 12),
            Text(
              t('cc.empty_tx'),
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

    return Dismissible(
      key: ValueKey('cc-txn-${tx.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.highlight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: AppIcon(AppIcons.trash, color: AppColors.surface, size: 22),
      ),
      confirmDismiss: (_) => _confirmDeleteTxn(tx),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tx.isInstallment
                  ? AppColors.accent.withAlpha(25)
                  : AppColors.highlight.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AppIcon(
              tx.isInstallment ? AppIcons.repeat : AppIcons.receipt,
              size: 16,
              color: tx.isInstallment ? AppColors.accent : AppColors.highlight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description.isNotEmpty ? tx.description : 'Transaksi',
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
            AppIcon(
              AppIcons.repeat,
              size: 48,
              color: AppColors.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: 12),
            Text(
              t('cc.empty_installments'),
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

    return Dismissible(
      key: ValueKey('cc-inst-${inst.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.highlight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppIcon(AppIcons.trash, color: AppColors.surface, size: 22),
      ),
      confirmDismiss: (_) => _confirmDeleteInst(inst),
      child: Container(
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
                  inst.description.isNotEmpty ? inst.description : 'Cicilan',
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
            '$progress / ${inst.totalMonths} bulan',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _infoColumn('Per bulan', formatCurrency(inst.monthlyAmount)),
              ),
              Expanded(
                child: _infoColumn('Total', formatCurrency(inst.totalAmount)),
              ),
            ],
          ),
        ],
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
    return 'tgl $day';
  }

  String _formatDate(String dateStr) {
    return formatDate(dateStr);
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
          final formatted = formatIdrInput(digits);
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
          title: Text(t('tx.add')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionCtrl,
                decoration: InputDecoration(
                  labelText: t('cc.desc_label'),
                  hintText: t('cc.desc_hint'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                focusNode: amountFocusNode,
                decoration: InputDecoration(
                  labelText: t('cc.amount_label'),
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
                  decoration: InputDecoration(
                    labelText: t('cc.date_label'),
                    border: OutlineInputBorder(),
                    suffixIcon: AppIcon(AppIcons.calendar),
                  ),
                  child: Text(
                    formatDate(selectedDate.toIso8601String().substring(0, 10)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('common.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
              ),
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
                      content: Text(success ? 'Transaksi kesimpen' : 'Gagal catat transaksi'),
                    ),
                  );
                }
              },
              child: Text(t('common.save')),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      descriptionCtrl.dispose();
      amountCtrl.dispose();
      amountFocusNode.dispose();
    });
  }
}
