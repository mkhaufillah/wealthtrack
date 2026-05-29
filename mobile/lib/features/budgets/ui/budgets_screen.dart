import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../../shared/utils/category_translator.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/transactions/ui/widgets/amount_field.dart';
import '../../home/providers/dashboard_provider.dart';
import '../providers/budget_provider.dart';
import '../models/budget_model.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      ref.read(dashboardProvider.notifier).load();
    });
  }

  String get _monthParam => DateFormat('yyyy-MM').format(_currentMonth);

  void _load() => ref.read(budgetProvider.notifier).load(_monthParam);

  void _prevMonth() {
    setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1));
    _load();
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _currentMonth = next);
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
                          : _buildBudgetList(state.items),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBudgetSheet(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMonthPicker() {
    final now = DateTime.now();
    final canGoNext =
        DateTime(_currentMonth.year, _currentMonth.month + 1).isBefore(
              DateTime(now.year, now.month + 1),
            );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevMonth),
          Text(
            DateFormat('MMMM yyyy').format(_currentMonth),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext ? _nextMonth : null,
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
        ],
      ),
    );
  }

  Widget _buildBudgetList(List<BudgetSummaryItem> items) {
    final totalBudget = items.fold<int>(0, (s, i) => s + i.budgetAmount);
    final totalSpent = items.fold<int>(0, (s, i) => s + i.actualSpent);
    final totalRemaining = items.fold<int>(0, (s, i) => s + i.remaining);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _buildSummaryCard(totalBudget, totalSpent, totalRemaining);
        }
        return _buildBudgetCard(items[i - 1]);
      },
    );
  }

  Widget _buildSummaryCard(int totalBudget, int totalSpent, int totalRemaining) {
    final dashboard = ref.watch(dashboardProvider);
    final balance = dashboard.balance;
    final diff = balance - totalRemaining;
    final isOverBudgeted = totalRemaining > balance;

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
              _summaryRow('Current Balance', formatCurrency(balance), AppColors.textPrimary),
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
                          ? 'Budget exceeds balance by ${formatCurrency(totalRemaining - balance)}'
                          : diff >= 0
                              ? 'Balance covers all budgets (${formatCurrency(diff)} extra)'
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
                  child: Text(translateCategory(item.categoryName),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
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
                  isOverBudget
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

  Future<void> _showAddBudgetSheet() async {
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
        onSaved: (catId, amount) {
          ref.read(budgetProvider.notifier).setBudget(catId, amount, _monthParam);
        },
      ),
    );
  }

  Future<void> _confirmDeleteBudget(BudgetSummaryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text('Remove budget for ${translateCategory(item.categoryName)}?'),
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

// ─── Add Budget Bottom Sheet ──────────────────────────────────

class _AddBudgetSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final String month;
  final Function(int categoryId, int amount) onSaved;

  const _AddBudgetSheet({
    required this.categories,
    required this.month,
    required this.onSaved,
  });

  @override
  State<_AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends State<_AddBudgetSheet> {
  final _amountCtrl = TextEditingController();
  int? _selectedCategoryId;
  bool _isSaving = false;

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
          const Text('Set Monthly Budget',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Category picker
          const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _selectedCategoryId,
            decoration: const InputDecoration(
              hintText: 'Select category',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: widget.categories.map((c) => DropdownMenuItem(
              value: c['id'] as int,
              child: Text('${c['icon'] ?? '📦'}  ${translateCategory(c['name'] as String)}'),
            )).toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 16),

          // Amount
          const Text('Monthly Limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          AmountField(controller: _amountCtrl),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Budget'),
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
    widget.onSaved(_selectedCategoryId!, amount);
    Navigator.pop(context);
  }
}
