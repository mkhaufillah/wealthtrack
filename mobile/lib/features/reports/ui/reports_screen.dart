import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets/charts_section.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/home/providers/dashboard_provider.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../../../shared/utils/date_formatter.dart';
import '../providers/report_provider.dart';
import '../models/report_model.dart';
import '../../budgets/models/budget_model.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _currentMonth;
  String _cycleLabel = '';
  int _userCycleDay = 1;
  List<BudgetSummaryItem> _budgetItems = [];
  List<UnbudgetedExpense> _uncategorizedExpenses = [];

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    // Load on first build — defer to post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadMonth();  // loads cycle info + data for current month
      // After load, adjust to latest viewable month and reload
      _currentMonth = _maxMonth();
      _loadMonth();
    });
  }

  DateTime _maxMonth() {
    if (_userCycleDay <= 1) return DateTime.now();
    final today = DateTime.now();
    if (today.day >= _userCycleDay) {
      return DateTime(today.year, today.month);
    }
    if (today.month == 1) {
      return DateTime(today.year - 1, 12);
    }
    return DateTime(today.year, today.month - 1);
  }

  String get _monthParam => DateFormat('yyyy-MM').format(_currentMonth);

  Future<void> _loadMonth() async {
    final monthStr = _monthParam;

    // Get user's cycle start day
    int cycleDay = 1;
    try {
      final api = ref.read(apiClientProvider);
      // Use mid-month as reference so cycle changes when navigated
      final refDate = DateFormat('yyyy-MM-15').format(_currentMonth);
      final cycleResp = await api.get('/summaries/cycle-info', queryParams: {'date': refDate});
      final cycleData = cycleResp.data;
      cycleDay = cycleData['cycle_start_day'] as int? ?? 1;
      _userCycleDay = cycleDay;
    } catch (_) {
      _userCycleDay = 1;
    }

    // Compute range locally using getCycleRangeForMonth — NOT from API.
    // API's date_from/date_to uses get_cycle_range (cycle containing ref date),
    // but reports need get_cycle_range_for_month (period for the month label).
    // These differ for D1-D15 (get_cycle_range shifts forward one month).
    final (dFrom, dTo) = getCycleRangeForMonth(monthStr, cycleDay);
    final firstDay = DateFormat('yyyy-MM-dd').format(dFrom);
    final lastDay = DateFormat('yyyy-MM-dd').format(dTo);

    // Build cycle label from dates (e.g. "25 Apr – 24 Mei 2026")
    _cycleLabel = '${DateFormat('dd MMM').format(dFrom)} – ${DateFormat('dd MMM yyyy').format(dTo)}';

    ref.read(reportProvider.notifier).load(monthStr, dateFrom: firstDay, dateTo: lastDay);
    ref.read(reportProvider.notifier).loadHousehold(dateFrom: firstDay, dateTo: lastDay);

    // Load 6-month trend for charts
    final trendFrom = DateFormat('yyyy-MM').format(
      DateTime(_currentMonth.year, _currentMonth.month - 5, 1),
    );
    ref.read(reportProvider.notifier).loadTrend(monthFrom: trendFrom, monthTo: monthStr);

    // Also load budget vs actual for this cycle
    _loadBudgets(monthStr, firstDay, lastDay);
  }

  Future<void> _loadBudgets(String month, String dateFrom, String dateTo) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/budgets/summary', queryParams: {
        'month': month,
        'use_cycle': 'true',
        'd_from_override': dateFrom,
        'd_to_override': dateTo,
      });
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _budgetItems = (data['items'] as List)
            .map((e) => BudgetSummaryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _uncategorizedExpenses = (data['uncategorized_expenses'] as List?)
                ?.map((e) => UnbudgetedExpense.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _budgetItems = [];
        _uncategorizedExpenses = [];
      });
    }
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
    final maxMonth = _maxMonth();
    if (next.isAfter(maxMonth)) return;
    setState(() {
      _currentMonth = next;
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportProvider);

    // Reload when transactions change (add/edit/transfer from other screens)
    ref.listen<int>(homeRefreshProvider, (prev, next) {
      if (prev != next && _currentMonth != null) _loadMonth();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          _buildMonthPicker(),
          Expanded(
            child: state.isLoading
                ? RefreshIndicator(
                    onRefresh: () async => _loadMonth(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))],
                    ),
                  )
                : state.error != null
                    ? RefreshIndicator(
                        onRefresh: () async => _loadMonth(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [SizedBox(height: 300, child: ErrorDisplay(message: state.error!, onRetry: _loadMonth))],
                        ),
                      )
                    : state.monthly != null
                        ? RefreshIndicator(
                            onRefresh: () async => _loadMonth(),
                            child: _buildContent(state),
                          )
                        : RefreshIndicator(
                            onRefresh: () async => _loadMonth(),
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))],
                            ),
                          ),
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
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
          ),
          Text(
            _cycleLabel.isNotEmpty ? _cycleLabel : DateFormat('MMMM yyyy').format(_currentMonth),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext ? _nextMonth : null,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ReportState state) {
    final report = state.monthly!;
    final children = [
        _buildSummaryCards(report),
        const SizedBox(height: 16),
        _buildExtraStats(report),
        const SizedBox(height: 20),
        if (_budgetItems.isNotEmpty) ...[
          _buildSectionHeader('Budget vs Actual', Icons.account_balance_wallet_outlined),
          const SizedBox(height: 8),
          _buildBudgetVsActual(),
          const SizedBox(height: 20),
        ],
        if (report.categories.isNotEmpty) ...[
          _buildSectionHeader('Category Breakdown', Icons.pie_chart_outline),
          const SizedBox(height: 8),
          _buildCategoryBreakdown(report.categories, report.totalExpense),
          const SizedBox(height: 16),
          buildPieChartSection(report.categories),
          const SizedBox(height: 16),
          _buildSectionHeader('Category Comparison', Icons.bar_chart_outlined),
          const SizedBox(height: 8),
          buildBarChartSection(report.categories),
          const SizedBox(height: 20),
        ],
        if (state.trend.length >= 2) ...[
          _buildSectionHeader('Monthly Trend', Icons.trending_up),
          const SizedBox(height: 8),
          buildTrendChartSection(state.trend),
          const SizedBox(height: 20),
        ],
        if (report.dailySnapshot.isNotEmpty) ...[
          _buildSectionHeader('Daily Breakdown', Icons.calendar_view_day),
          const SizedBox(height: 8),
          _buildDailySnapshot(report.dailySnapshot),
          const SizedBox(height: 20),
        ],
        if (state.household != null && state.household!.byUser.length > 1) ...[
          _buildSectionHeader('Household Split', Icons.people_outline),
          const SizedBox(height: 8),
          _buildHouseholdSplit(state.household!),
          const SizedBox(height: 20),
        ],
        if (state.household != null && state.household!.byCategory.isNotEmpty && state.household!.byUser.length > 1) ...[
          _buildSectionHeader('Household Category Breakdown', Icons.pie_chart_outline),
          const SizedBox(height: 8),
          _buildHouseholdCategoryBreakdown(state.household!.byCategory, state.household!.totalExpense),
          const SizedBox(height: 20),
        ],
        if (state.householdTransactions.isNotEmpty) ...[
          _buildSectionHeader('Household Daily Breakdown', Icons.calendar_view_day),
          const SizedBox(height: 8),
          _buildHouseholdDailyBreakdown(state.householdTransactions),
        ],
        const SizedBox(height: 24),
        _buildExportButton(),
      ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildSummaryCards(MonthlyReport report) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Income', report.totalIncome, AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Expense', report.totalExpense, AppColors.highlight)),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Balance',
            report.balance,
            report.balance >= 0 ? AppColors.success : AppColors.highlight,
          ),
        ),
      ],
    );
  }

  Widget _buildExtraStats(MonthlyReport report) {
    final income = report.totalIncome;
    final expense = report.totalExpense;

    // Find savings & investment amounts
    final savingsExpense = report.categories
        .where((c) => c.categoryNameEn == 'Savings & Investment')
        .fold<int>(0, (sum, c) => sum + c.total);
    final savingsIncome = report.incomeCategories
        .where((c) => c.categoryNameEn == 'Saving & Investment')
        .fold<int>(0, (sum, c) => sum + c.total);

    // Adjusted savings rate: (income - expense + savingsExpense - savingsIncome) / income * 100
    final adjustedNumerator = (income - expense) + (savingsExpense - savingsIncome);
    final savingsRate = income > 0 ? (adjustedNumerator / income * 100) : 0.0;

    // Compute cycle days from the cycle label
    final cycleDays = _cycleLabel.isNotEmpty ? 30 : 30; // fallback
    // Parse actual days from cycle dates
    int actualDays = 30;
    if (_cycleLabel.isNotEmpty) {
      // The label format is "25 May – 24 Jun 2026" — extract day diff
      final parts = _cycleLabel.split(' – ');
      if (parts.length == 2) {
        try {
          final from = DateFormat('dd MMM').parse(parts[0]);
          final to = DateFormat('dd MMM yyyy').parse(parts[1]);
          actualDays = to.difference(from).inDays;
          if (actualDays <= 0) actualDays = 30;
        } catch (_) {
          actualDays = 30;
        }
      }
    }
    final dailyAvg = actualDays > 0 ? expense ~/ actualDays : 0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Savings Rate',
            savingsRate.round(),
            savingsRate >= 0 ? AppColors.success : AppColors.highlight,
            suffix: '%',
            isRate: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Daily Avg',
            dailyAvg,
            AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int amount, Color color, {String suffix = '', bool isRate = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            isRate ? '${amount}$suffix' : formatCurrency(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetVsActual() {
    final sorted = List<BudgetSummaryItem>.from(_budgetItems)
      ..sort((a, b) => (b.percentage - a.percentage).round());
    final totalBudget = _budgetItems.fold<int>(0, (s, i) => s + i.budgetAmount);
    final totalSpent = _budgetItems.fold<int>(0, (s, i) => s + i.actualSpent);

    return Column(
      children: [
        // Mini summary row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('Total Budget', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              Text(formatCurrency(totalBudget),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Total Spent', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              Text(formatCurrency(totalSpent),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: totalSpent > totalBudget ? AppColors.highlight : AppColors.textPrimary)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Per-category budget vs actual
        ...sorted.map((item) {
          final isOver = item.remaining < 0;
          final pct = item.percentage;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text(item.categoryIcon, style: const TextStyle(fontSize: 16))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.categoryNameEn.isNotEmpty ? item.categoryNameEn : item.categoryName,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatCurrency(item.actualSpent),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOver ? AppColors.highlight : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  child: Text(
                    '/ ${formatCurrency(item.budgetAmount)}',
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isOver ? AppColors.highlight
                                : pct >= 70 ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 28,
                  child: Text(
                    isOver ? '🔴' : pct >= 70 ? '⚠️' : '✅',
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }),
        if (_uncategorizedExpenses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_uncategorizedExpenses.length} categor${_uncategorizedExpenses.length > 1 ? 'ies' : 'y'} without budget',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
                Text(
                  formatCurrency(_uncategorizedExpenses.fold<int>(0, (s, e) => s + e.total)),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown(List<CategoryBreakdown> categories, int totalExpense) {
    // Sort by total descending
    final sorted = List<CategoryBreakdown>.from(categories)
      ..sort((a, b) => b.total.compareTo(a.total));

    return Column(
      children: sorted.map((cat) {
        final fraction = totalExpense > 0 ? cat.total / totalExpense : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(cat.icon, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  cat.categoryNameEn.isNotEmpty ? cat.categoryNameEn : cat.categoryName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cat.categoryName.contains('Makan')
                          ? Colors.orange
                          : cat.categoryName.contains('Transport')
                              ? Colors.blue
                              : cat.categoryName.contains('Housing') ||
                                        cat.categoryName.contains('Rumah')
                                    ? Colors.purple
                                    : cat.categoryName.contains('Health') ||
                                              cat.categoryName.contains('Kesehatan')
                                          ? Colors.red
                                          : cat.categoryName.contains('Entertainment') ||
                                                    cat.categoryName.contains('Hiburan')
                                                ? Colors.teal
                                                : Colors.indigo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 65,
                child: Text(
                  '${cat.percentage.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHouseholdSplit(HouseholdReport hh) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: hh.byUser.map((u) {
          final total = u.totalExpense + (u.totalIncome);
          final maxTotal = hh.byUser
              .map((e) => e.totalExpense + e.totalIncome)
              .reduce((a, b) => a > b ? a : b);
          final fraction = maxTotal > 0 ? total / maxTotal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: u.displayName == 'Nahda'
                      ? (isDark ? Colors.pink.shade200.withOpacity(0.3) : Colors.pink.shade50)
                      : (isDark ? Colors.blue.shade200.withOpacity(0.3) : Colors.blue.shade50),
                  child: Text(
                    u.displayName.isNotEmpty ? u.displayName[0] : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : (u.displayName == 'Nahda'
                          ? Colors.pink.shade700
                          : Colors.blue.shade700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Text(
                    u.displayName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 8,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            u.displayName == 'Nahda'
                                ? (isDark ? Colors.pink.shade300.withOpacity(0.7) : Colors.pink.shade300)
                                : (isDark ? Colors.blue.shade300.withOpacity(0.7) : Colors.blue.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'I: ' + formatCurrency(u.totalIncome) + ' / E: ' + formatCurrency(u.totalExpense),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDailySnapshot(List<DailySnapshot> days) {
    // Show only days that have activity
    final filtered = days.where((d) => d.expense > 0 || d.income > 0).toList();
    if (filtered.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No transactions this month',
          style: TextStyle(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: filtered.reversed.map((day) {
        final date = DateTime.tryParse(day.date);
        final dayLabel = date != null ? DateFormat('MMM dd').format(date) : day.date;
        final weekday = date != null ? DateFormat('E').format(date) : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      weekday,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (day.expense > 0)
                      Text(
                        '-${formatCurrency(day.expense)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.highlight,
                        ),
                      ),
                    if (day.income > 0)
                      Text(
                        '+${formatCurrency(day.income)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHouseholdCategoryBreakdown(List<CategoryBreakdown> categories, int totalExpense) {
    final sorted = List<CategoryBreakdown>.from(categories)
      ..sort((a, b) => b.total.compareTo(a.total));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
      children: sorted.map((cat) {
        final fraction = totalExpense > 0 ? cat.total / totalExpense : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(cat.icon, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  cat.categoryNameEn.isNotEmpty ? cat.categoryNameEn : cat.categoryName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cat.categoryName.contains('Makan')
                          ? Colors.orange
                          : cat.categoryName.contains('Transport')
                              ? Colors.blue
                              : cat.categoryName.contains('Housing') ||
                                        cat.categoryName.contains('Rumah')
                                    ? Colors.purple
                                    : cat.categoryName.contains('Health') ||
                                              cat.categoryName.contains('Kesehatan')
                                          ? Colors.red
                                          : cat.categoryName.contains('Entertainment') ||
                                                    cat.categoryName.contains('Hiburan')
                                                ? Colors.teal
                                                : Colors.indigo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 65,
                child: Text(
                  '${cat.percentage.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      ),
    );
  }

  Widget _buildHouseholdDailyBreakdown(List<Map<String, dynamic>> txns) {
    // Group by date
    final Map<String, List<Map<String, dynamic>>> byDate = {};
    for (final txn in txns) {
      final txnDate = txn['date'] as String? ?? '';
      byDate.putIfAbsent(txnDate, () => []).add(txn);
    }

    // Sort dates descending
    final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: sortedDates.map((dateStr) {
        final dayTxns = byDate[dateStr]!;
        final totalExpense = dayTxns
            .where((t) => t['type'] == 'expense')
            .fold<int>(0, (s, t) => s + ((t['amount'] ?? 0) as int));
        final totalIncome = dayTxns
            .where((t) => t['type'] == 'income')
            .fold<int>(0, (s, t) => s + ((t['amount'] ?? 0) as int));

        final parsed = DateTime.tryParse(dateStr);
        final dayLabel = parsed != null ? DateFormat('MMM dd').format(parsed) : dateStr;
        final weekday = parsed != null ? DateFormat('E').format(parsed) : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(
                  children: [
                    Text(
                      dayLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      weekday,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'E: ' + formatCurrency(totalExpense),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.highlight,
                      ),
                    ),
                    if (totalIncome > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        'I: ' + formatCurrency(totalIncome),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.divider),
              // Transactions for this day
              ...dayTxns.map((txn) {
                final amount = txn['amount'] ?? 0;
                final isExpense = txn['type'] == 'expense';
                final user = txn['user'] as Map<String, dynamic>? ?? {};
                final userName = user['display_name'] as String? ?? '';
                final category = txn['category'] as Map<String, dynamic>? ?? {};
                final catIcon = category['icon'] as String? ?? '';
                final catName = category['name'] as String? ?? '';
                final desc = txn['description'] as String? ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(catIcon, style: const TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              desc.isNotEmpty ? desc : catName,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (userName.isNotEmpty)
                              Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${isExpense ? '-' : '+'}' + formatCurrency(amount is int ? amount : (amount as num).toInt()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isExpense ? AppColors.highlight : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _exportYearly,
        icon: const Icon(Icons.file_download_outlined, size: 18),
        label: const Text('Export Yearly (Excel)'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _exportYearly() async {
    try {
      final api = ref.read(apiClientProvider);
      final scaffold = ScaffoldMessenger.of(context);
      final snackbarColor = Theme.of(context).colorScheme.onInverseSurface;

      scaffold.showSnackBar(
        SnackBar(content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: snackbarColor)),
            SizedBox(width: 12),
            const Text('Generating export...'),
          ],
        )),
      );

      final year = _currentMonth.year;
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/wealthtrack_$year.xlsx';

      await api.download(
        '/exports/yearly?year=$year',
        filePath,
      );

      scaffold.hideCurrentSnackBar();
      await Share.shareXFiles([XFile(filePath)], text: 'WealthTrack $year Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

}

// ─── Chart Widgets ──────────────────────────────────────────

final List<Color> chartColors = [
  Colors.orange, Colors.blue, Colors.purple, Colors.red, Colors.teal,
  Colors.green, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
];
