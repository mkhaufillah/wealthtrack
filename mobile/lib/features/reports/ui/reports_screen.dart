import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets/charts_section.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../providers/report_provider.dart';
import '../models/report_model.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    // Load on first build — defer to post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMonth();
    });
  }

  String get _monthParam => DateFormat('yyyy-MM').format(_currentMonth);

  void _loadMonth() {
    final monthStr = _monthParam;
    final firstDay = DateFormat('yyyy-MM-01').format(_currentMonth);
    final lastDay = DateFormat('yyyy-MM-dd').format(
      DateTime(_currentMonth.year, _currentMonth.month + 1, 0),
    );
    ref.read(reportProvider.notifier).load(monthStr);
    ref.read(reportProvider.notifier).loadHousehold(dateFrom: firstDay, dateTo: lastDay);

    // Load 6-month trend for charts
    final trendFrom = DateFormat('yyyy-MM').format(
      DateTime(_currentMonth.year, _currentMonth.month - 5, 1),
    );
    ref.read(reportProvider.notifier).loadTrend(monthFrom: trendFrom, monthTo: monthStr);
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
    if (next.isAfter(DateTime.now())) return;
    setState(() {
      _currentMonth = next;
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: () async => _loadMonth(),
        child: Column(
          children: [
            _buildMonthPicker(),
            Expanded(
              child: state.isLoading
                  ? const LoadingIndicator()
                  : state.error != null
                      ? ErrorDisplay(message: state.error!, onRetry: _loadMonth)
                      : state.monthly != null
                          ? _buildContent(state)
                          : const LoadingIndicator(),
            ),
          ],
        ),
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
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
          ),
          Text(
            DateFormat('MMMM yyyy').format(_currentMonth),
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
        const SizedBox(height: 20),
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

  Widget _buildStatCard(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            formatCurrency(amount),
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
                  cat.categoryName,
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
                                                : AppColors.primary,
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
                  backgroundColor: u.displayName == 'Nahda'
                      ? Colors.pink.shade100
                      : Colors.blue.shade100,
                  child: Text(
                    u.displayName.isNotEmpty ? u.displayName[0] : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: u.displayName == 'Nahda'
                          ? Colors.pink.shade700
                          : Colors.blue.shade700,
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
                                ? Colors.pink.shade300
                                : Colors.blue.shade300,
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
                  cat.categoryName,
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
                                                : AppColors.primary,
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

      scaffold.showSnackBar(
        const SnackBar(content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Generating export...'),
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
