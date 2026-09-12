import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/category_glyph.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets/charts_section.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/home/providers/dashboard_provider.dart';
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
    // Cycle month = month in which the cycle ENDS.
    // If today is still before cycle_day, the active cycle ends this month.
    // If today is on/after cycle_day, the active cycle ends next month.
    final today = DateTime.now();
    if (today.day < _userCycleDay) {
      return DateTime(today.year, today.month);
    }
    if (today.month == 12) {
      return DateTime(today.year + 1, 1);
    }
    return DateTime(today.year, today.month + 1);
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
    } catch (e) {
      debugPrint('ERROR: $e');
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
    _cycleLabel = '${formatDayMonth(dFrom)} ${dFrom.year} – ${formatDayMonth(dTo)} ${dTo.year}';

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
    } catch (e) {
      debugPrint('ERROR: $e');
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
      if (prev != next) _loadMonth();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t('report.title'))),
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
            icon: AppIcon(AppIcons.back),
            onPressed: _prevMonth,
          ),
          Text(
            _cycleLabel.isNotEmpty ? _cycleLabel : formatMonthYear(_currentMonth),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: AppIcon(AppIcons.next),
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
          _buildSectionHeader(t('report.vs_budget')),
          const SizedBox(height: 8),
          _buildBudgetVsActual(),
          const SizedBox(height: 20),
        ],
        if (report.categories.isNotEmpty) ...[
          _buildSectionHeader(t('report.by_cat')),
          const SizedBox(height: 8),
          _buildCategoryBreakdown(report.categories, report.totalExpense),
          const SizedBox(height: 16),
          buildPieChartSection(report.categories),
          const SizedBox(height: 16),
          _buildSectionHeader(t('report.compare_cat')),
          const SizedBox(height: 8),
          buildBarChartSection(report.categories),
          const SizedBox(height: 20),
        ],
        if (state.trend.length >= 2) ...[
          _buildSectionHeader(t('report.trend')),
          const SizedBox(height: 8),
          buildTrendChartSection(state.trend),
          const SizedBox(height: 20),
        ],
        if (report.dailySnapshot.isNotEmpty) ...[
          _buildSectionHeader(t('report.daily')),
          const SizedBox(height: 8),
          _buildDailySnapshot(report.dailySnapshot),
          const SizedBox(height: 20),
        ],
        if (state.household != null && state.household!.byUser.length > 1) ...[
          _buildSectionHeader(t('report.hh_split')),
          const SizedBox(height: 8),
          _buildHouseholdSplit(state.household!),
          const SizedBox(height: 20),
        ],
        if (state.household != null && state.household!.byCategory.isNotEmpty && state.household!.byUser.length > 1) ...[
          _buildSectionHeader(t('report.hh_cat')),
          const SizedBox(height: 8),
          _buildHouseholdCategoryBreakdown(state.household!.byCategory, state.household!.totalExpense),
          const SizedBox(height: 20),
        ],
        if (state.householdTransactions.isNotEmpty) ...[
          _buildSectionHeader(t('report.hh_daily')),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.heroFill,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(child: _buildStatCard(t('report.income'), report.totalIncome, AppColors.success)),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCard(t('report.expense'), report.totalExpense, AppColors.highlight)),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              t('report.balance'),
              report.balance,
              report.balance >= 0 ? AppColors.success : AppColors.highlight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraStats(MonthlyReport report) {
    // Savings rate + daily avg now come server-computed from /summaries/monthly.
    final savingsRate = report.savingsRate;
    final dailyAvg = report.dailyAvgExpense;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            t('report.savings_rate'),
            savingsRate.round(),
            savingsRate >= 0 ? AppColors.success : AppColors.highlight,
            suffix: '%',
            isRate: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            t('report.daily_avg'),
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
            isRate ? '${amount}$suffix' : formatCurrencyCompact(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                child: Text(t('budget.total'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              Text(formatCurrency(totalBudget),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t('budget.spent'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                CategoryGlyph(icon: item.categoryIcon, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    catLabel(name: item.categoryName, copyKey: item.copyKey),
                    style: TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatCurrencyCompact(item.actualSpent),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isOver ? AppColors.highlight : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 55,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '/ ${formatCurrencyCompact(item.budgetAmount)}',
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      textAlign: TextAlign.right,
                    ),
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
                  child: AppIcon(
                    isOver
                        ? AppIcons.alert
                        : pct >= 70
                            ? AppIcons.alert
                            : AppIcons.check,
                    size: 16,
                    color: isOver
                        ? AppColors.highlight
                        : pct >= 70
                            ? AppColors.warning
                            : AppColors.success,
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
                AppIcon(AppIcons.info, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('reports.uncategorized_n').replaceAll('{n}', '${_uncategorizedExpenses.length}'),
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
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
              CategoryGlyph(icon: cat.icon, size: 28),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  catLabel(name: cat.categoryName, copyKey: cat.copyKey),
                  style: TextStyle(fontSize: 13),
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
                      AppColors.chartPalette[
                        cat.categoryName.hashCode.abs() % AppColors.chartPalette.length
                      ],
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
                  backgroundColor: AppColors.avatarBackground(u.displayName),
                  child: Text(
                    u.displayName.isNotEmpty ? u.displayName[0] : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.avatarText(u.displayName),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Text(
                    u.displayName,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                            AppColors.avatarColor(u.displayName).withOpacity(0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t('report.abbr_income') + ': ' + formatCurrency(u.totalIncome) + ' / ' + t('report.abbr_expense') + ': ' + formatCurrency(u.totalExpense),
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
          t('reports.empty_month'),
          style: TextStyle(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: filtered.reversed.map((day) {
        final date = DateTime.tryParse(day.date);
        final dayLabel = date != null ? formatDayMonth(date) : day.date;
        final weekday = date != null ? formatWeekday(date) : '';
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
                      style: TextStyle(
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
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.highlight,
                        ),
                      ),
                    if (day.income > 0)
                      Text(
                        '+${formatCurrency(day.income)}',
                        style: TextStyle(
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
              CategoryGlyph(icon: cat.icon, size: 28),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  catLabel(name: cat.categoryName, copyKey: cat.copyKey),
                  style: TextStyle(fontSize: 13),
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
                      AppColors.chartPalette[
                        cat.categoryName.hashCode.abs() % AppColors.chartPalette.length
                      ],
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
        final dayLabel = parsed != null ? formatDayMonth(parsed) : dateStr;
        final weekday = parsed != null ? formatWeekday(parsed) : '';

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
                      style: TextStyle(
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
                      t('report.abbr_expense') + ': ' + formatCurrency(totalExpense),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.highlight,
                      ),
                    ),
                    if (totalIncome > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        t('report.abbr_income') + ': ' + formatCurrency(totalIncome),
                        style: TextStyle(
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
                final catName = catLabel(name: category['name'] as String? ?? '', copyKey: category['copy_key'] as String?);
                final desc = txn['description'] as String? ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      CategoryGlyph(icon: catIcon, size: 24),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              desc.isNotEmpty ? desc : catName,
                              style: TextStyle(fontSize: 12),
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
        icon: AppIcon(AppIcons.send, size: 18),
        label: Text(t('report.export')),
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
            Text(t('common.making_file')),
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
      await Share.shareXFiles([XFile(filePath)], text: t('common.export_year').replaceAll('{year}', year.toString()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common.failed_download') + ': ' + e.toString())),
      );
    }
  }

}

// ─── Chart Widgets ──────────────────────────────────────────

final List<Color> chartColors = AppColors.chartPalette;
