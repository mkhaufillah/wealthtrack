import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/transactions/ui/widgets/amount_field.dart';
import '../providers/budget_provider.dart';
import '../models/budget_model.dart';
import 'budget_suggestion_sheet.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  late DateTime _currentMonth;
  String _cycleLabel = '';
  int _userCycleDay = 1;
  String? _cycleDateFrom;
  String? _cycleDateTo;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First load cycle info for the current month, then jump to latest viewable
      await _loadCycleInfo();
      _currentMonth = _maxMonth();
      await _loadCycleInfo();  // re-fetch with the correct month
      _load();
    });
  }

  DateTime _maxMonth() {
    if (_userCycleDay <= 1) return DateTime.now();
    // With new month=start logic:
    // - today >= cycle: budget starting this month is current
    // - today < cycle: still in previous month's budget period
    final today = DateTime.now();
    if (today.day >= _userCycleDay) {
      return DateTime(today.year, today.month);
    }
    if (today.month == 1) {
      return DateTime(today.year - 1, 12);
    }
    return DateTime(today.year, today.month - 1);
  }

  Future<void> _loadCycleInfo() async {
    try {
      final api = ref.read(apiClientProvider);
      // Use mid-month as reference so cycle changes when navigated
      final refDate = DateFormat('yyyy-MM-15').format(_currentMonth);
      final resp = await api.get('/summaries/cycle-info', queryParams: {'date': refDate});
      final data = resp.data;
      final cycleStartDay = data['cycle_start_day'] as int? ?? 1;
      if (!mounted) return;
      setState(() {
        _userCycleDay = cycleStartDay;
        // Compute range locally using getCycleRangeForMonth — NOT from API.
        // API's date_from/date_to uses get_cycle_range (cycle containing ref date),
        // but budgets need get_cycle_range_for_month (budget period for month label).
        // These differ for D1-D15 (get_cycle_range shifts forward one month).
        final (dFrom, dTo) = getCycleRangeForMonth(_monthParam, cycleStartDay);
        _cycleDateFrom = DateFormat('yyyy-MM-dd').format(dFrom);
        _cycleDateTo = DateFormat('yyyy-MM-dd').format(dTo);
        _cycleLabel = '${DateFormat('dd MMM yyyy').format(dFrom)} – ${DateFormat('dd MMM yyyy').format(dTo)}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cycleLabel = '';
        _userCycleDay = 1;
        _cycleDateFrom = null;
        _cycleDateTo = null;
      });
    }
  }

  String get _monthParam => DateFormat('yyyy-MM').format(_currentMonth);

  void _load() {
    ref.read(budgetProvider.notifier).load(_monthParam,
        dateFrom: _cycleDateFrom, dateTo: _cycleDateTo);
  }

  Future<void> _prevMonth() async {
    setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1));
    await _loadCycleInfo();
    _load();
  }

  Future<void> _nextMonth() async {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
    final maxMonth = _maxMonth();
    if (next.isAfter(maxMonth)) return;
    setState(() => _currentMonth = next);
    await _loadCycleInfo();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(budgetProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Budgets')),
      body: Column(
        children: [
          _buildMonthPicker(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.read(budgetProvider.notifier).load(_monthParam),
              child: state.isLoading && state.items.isEmpty
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))])
                  : state.error != null && state.items.isEmpty
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 300, child: ErrorDisplay(message: state.error!, onRetry: _load))])
                      : state.items.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) => SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                  child: _buildEmptyState(),
                                ),
                              ),
                            )
                          : _buildBudgetList(state.items, state.uncategorizedExpenses),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'ai_suggestions',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => BudgetSuggestionSheet(month: _monthParam),
            ),
            backgroundColor: AppColors.accent,
            child: const Icon(Icons.auto_awesome, size: 20),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add_budget',
            onPressed: () => _showAddBudgetSheet(),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    final maxMonth = _maxMonth();
    final canGoNext =
        DateTime(_currentMonth.year, _currentMonth.month + 1).isBefore(
              DateTime(maxMonth.year, maxMonth.month + 1),
            );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _prevMonth()),
          Text(
            _cycleLabel.isNotEmpty ? _cycleLabel : DateFormat('MMMM yyyy').format(_currentMonth),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext ? () => _nextMonth() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('No budgets set for this month',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Tap + to add a spending limit per category',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => BudgetSuggestionSheet(month: _monthParam),
            ),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI Suggestions'),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetList(List<BudgetSummaryItem> items, List<UnbudgetedExpense> uncategorized) {
    final totalBudget = items.fold<int>(0, (s, i) => s + i.budgetAmount);
    final totalSpent = items.fold<int>(0, (s, i) => s + i.actualSpent);
    final totalRemaining = items.fold<int>(0, (s, i) => s + i.remaining);
    final totalUncategorized = uncategorized.fold<int>(0, (s, i) => s + i.total);

    // Extra items: summary card + budget cards + (if any) section header + each uncategorized category
    final extraCount = uncategorized.isNotEmpty ? 1 + uncategorized.length : 0;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
      itemCount: items.length + 1 + extraCount,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _buildSummaryCard(totalBudget, totalSpent, totalRemaining);
        }
        final budgetIndex = i - 1;
        if (budgetIndex < items.length) {
          return _buildBudgetCard(items[budgetIndex]);
        }
        // Uncategorized section
        final uncatIndex = budgetIndex - items.length;
        if (uncatIndex == 0) {
          return _buildUncategorizedHeader(totalUncategorized);
        }
        return _buildUncategorizedItem(uncategorized[uncatIndex - 1]);
      },
    );
  }

  Widget _buildSummaryCard(int totalBudget, int totalSpent, int totalRemaining) {
    final state = ref.watch(budgetProvider);
    final income = state.totalIncome;
    final diff = income - totalBudget;
    final isOverBudgeted = totalBudget > income;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    child: Icon(Icons.pie_chart_outline, color: AppColors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Budget Overview',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              _summaryRow('Total Budget', formatCurrency(totalBudget), AppColors.textPrimary),
              const SizedBox(height: 6),
              _summaryRow('Total Spent', formatCurrency(totalSpent), AppColors.highlight),
              const SizedBox(height: 6),
              _summaryRow('Remaining', formatCurrency(totalRemaining),
                  totalRemaining >= 0 ? AppColors.success : AppColors.highlight),
              Divider(height: 24, color: AppColors.divider),
              _summaryRow('Total Income', formatCurrency(income), AppColors.textPrimary),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isOverBudgeted ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    size: 14,
                    color: isOverBudgeted ? AppColors.warning : AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isOverBudgeted
                          ? 'Budget exceeds income by ${formatCurrency(totalBudget - income)}'
                          : diff >= 0
                              ? 'Income covers all budgets (${formatCurrency(diff)} extra)'
                              : 'Shortfall of ${formatCurrency(-diff)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOverBudgeted ? AppColors.warning : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
      ],
    );
  }

  Widget _buildUncategorizedHeader(int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Outside Budget',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'You have spending in categories without a budget. Consider adding budgets for these categories.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withOpacity(0.8)),
              ),
              const SizedBox(height: 12),
              ...List.generate(1, (_) => _summaryRow(
                'Total', formatCurrency(total), AppColors.warning,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUncategorizedItem(UnbudgetedExpense item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(item.categoryIcon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.categoryNameEn.isNotEmpty ? item.categoryNameEn : item.categoryName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              Text(formatCurrency(item.total),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warning)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetCard(BudgetSummaryItem item) {
    final isOverBudget = item.percentage >= 100;
    final isWarning = item.percentage >= 70 && item.percentage < 100;
    final isHealthy = item.percentage < 70;

    Color barColor;
    if (isOverBudget) {
      barColor = AppColors.highlight;
    } else if (isWarning) {
      barColor = AppColors.warning;
    } else {
      barColor = AppColors.success;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(item.categoryIcon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.categoryNameEn.isNotEmpty ? item.categoryNameEn : item.categoryName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                // Cycle date range badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    () {
                      final (from, to) = getCycleRangeForMonth(_monthParam, item.cycleOn);
                      return '${DateFormat('dd MMM').format(from)} – ${DateFormat('dd MMM').format(to)}';
                    }(),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Edit button
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _showAddBudgetSheet(existingItem: item),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                // Delete button
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _confirmDeleteBudget(item),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.highlight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.delete_outline, size: 16, color: AppColors.highlight),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency(item.actualSpent),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isOverBudget ? AppColors.highlight : AppColors.textPrimary,
                        )),
                    Text('/ ${formatCurrency(item.budgetAmount)}',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: item.percentage / 100,
                minHeight: 10,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${item.percentage.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isOverBudget ? AppColors.highlight : AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  item.remaining <= 0 && item.percentage == 100
                      ? 'Budget exhausted'
                      : isOverBudget
                          ? 'Over by ${formatCurrency(item.actualSpent - item.budgetAmount)}'
                          : '${formatCurrency(item.remaining)} remaining',
                  style: TextStyle(
                    fontSize: 12,
                    color: isOverBudget ? AppColors.highlight : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddBudgetSheet({BudgetSummaryItem? existingItem}) async {
    // Load categories for the picker
    final api = ref.read(apiClientProvider);
    List<Map<String, dynamic>> categories = [];
    try {
      final res = await api.get('/categories', queryParams: {'type': 'expense'});
      categories = List<Map<String, dynamic>>.from(res.data);
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddBudgetSheet(
        categories: categories,
        month: _monthParam,
        defaultCycleDay: _userCycleDay,
        existingItem: existingItem,
        onSaved: (catId, amount, cycleOn) {
          ref.read(budgetProvider.notifier).setBudget(catId, amount, _monthParam, cycleOn: cycleOn);
        },
      ),
    );
  }

  Future<void> _confirmDeleteBudget(BudgetSummaryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text('Remove budget for ${item.categoryNameEn.isNotEmpty ? item.categoryNameEn : item.categoryName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.highlight),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(budgetProvider.notifier).deleteBudget(item.id);
    }
  }
}

// ─── Add / Edit Budget Bottom Sheet ───────────────────────────

class _AddBudgetSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final String month;
  final int defaultCycleDay;
  final BudgetSummaryItem? existingItem;
  final void Function(int categoryId, int amount, int? cycleOn) onSaved;

  const _AddBudgetSheet({
    required this.categories,
    required this.month,
    required this.defaultCycleDay,
    this.existingItem,
    required this.onSaved,
  });

  @override
  State<_AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends State<_AddBudgetSheet> {
  final _amountCtrl = TextEditingController();
  int? _selectedCategoryId;
  int _cycleOn = 1;
  bool _isSaving = false;
  int? _existingBudgetId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingItem;
    if (existing != null) {
      // Editing mode: pre-fill values
      _selectedCategoryId = existing.categoryId;
      _amountCtrl.text = existing.budgetAmount.toString();
      _cycleOn = existing.cycleOn;  // use budget's stored cycle, not user's current
    } else {
      // New budget: default to user's current cycle
      _cycleOn = widget.defaultCycleDay;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.existingItem != null ? 'Edit Budget' : 'Set Monthly Budget',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          // Category picker
          const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          if (widget.existingItem != null) ...[
            // Edit mode: readonly category display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.divider.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(widget.existingItem!.categoryIcon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Text(
                    (widget.existingItem!.categoryNameEn.isNotEmpty ? widget.existingItem!.categoryNameEn : widget.existingItem!.categoryName),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ] else ...[
            // New budget: category dropdown
            DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                hintText: 'Select category',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: widget.categories.map((c) => DropdownMenuItem(
                value: c['id'] as int,
                child: Text('${c['icon'] ?? '📦'}  ${(c['name_en'] as String? ?? c['name']) as String}'),
              )).toList(),
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
          ],
          const SizedBox(height: 16),

          // Amount
          const Text('Monthly Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          AmountField(controller: _amountCtrl),
          const SizedBox(height: 16),

          // Cycle Day picker
          const Text('Billing Cycle Day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _cycleOn,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Select cycle day',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: List.generate(28, (i) => DropdownMenuItem<int>(
              value: i + 1,
              child: Text('Day ${i + 1}', style: TextStyle(color: AppColors.textPrimary)),
            )),
            onChanged: (v) {
              if (v != null) setState(() => _cycleOn = v);
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Actual spending is computed from this cycle day of previous month\nto day before this cycle day of current month.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.existingItem != null ? 'Update Budget' : 'Save Budget'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedCategoryId == null) return;
    final amount = int.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    widget.onSaved(_selectedCategoryId!, amount, _cycleOn);
    Navigator.pop(context);
  }
}
