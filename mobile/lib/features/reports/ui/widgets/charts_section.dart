import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/category_translator.dart';
import '../../models/report_model.dart';

/// Color palette used across all charts
const List<Color> chartColors = [
  Colors.orange, Colors.blue, Colors.purple, Colors.red, Colors.teal,
  Colors.green, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
];

/// Donut/pie chart — category breakdown of expenses.
Widget buildPieChartSection(List<CategoryBreakdown> categories) {
  if (categories.isEmpty) return const SizedBox.shrink();
  final sorted = List<CategoryBreakdown>.from(categories)
    ..sort((a, b) => b.total.compareTo(a.total));
  final total = sorted.fold<int>(0, (s, c) => s + c.total);

  return SizedBox(
    height: 220,
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: List.generate(sorted.length, (i) {
                final pct = total > 0 ? sorted[i].total / total : 0.0;
                return PieChartSectionData(
                  value: pct * 100,
                  color: chartColors[i % chartColors.length],
                  radius: 50,
                  title: pct >= 0.05 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                  titleStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                );
              }),
              centerSpaceRadius: 30,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: sorted.take(6).map((cat) {
              final idx = sorted.indexOf(cat);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: chartColors[idx % chartColors.length],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${cat.icon} ${translateCategory(cat.categoryNameEn.isNotEmpty ? cat.categoryNameEn : cat.categoryName)}',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  );
}

/// Horizontal bar chart — category comparison.
Widget buildBarChartSection(List<CategoryBreakdown> categories) {
  if (categories.isEmpty) return const SizedBox.shrink();
  final sorted = List<CategoryBreakdown>.from(categories)
    ..sort((a, b) => b.total.compareTo(a.total));
  final maxVal = sorted.first.total;

  return Column(
    children: sorted.take(8).map((cat) {
      final idx = sorted.indexOf(cat);
      final fraction = maxVal > 0 ? cat.total / maxVal : 0.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 24, child: Text(cat.icon, style: const TextStyle(fontSize: 14))),
            const SizedBox(width: 6),
            SizedBox(
              width: 65,
              child: Text(
                formatCurrency(cat.total),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 14,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(chartColors[idx % chartColors.length]),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

/// Line chart — multi-month income vs expense trend.
Widget buildTrendChartSection(List<MonthlyTrend> trend) {
  if (trend.length < 2) return const SizedBox.shrink();

  final spotsIncome = <FlSpot>[];
  final spotsExpense = <FlSpot>[];
  double maxVal = 0;

  for (var i = 0; i < trend.length; i++) {
    final t = trend[i];
    spotsIncome.add(FlSpot(i.toDouble(), t.totalIncome.toDouble()));
    spotsExpense.add(FlSpot(i.toDouble(), t.totalExpense.toDouble()));
    if (t.totalIncome > maxVal) maxVal = t.totalIncome.toDouble();
    if (t.totalExpense > maxVal) maxVal = t.totalExpense.toDouble();
  }

  final labels = trend.map((t) {
    final parts = t.month.split('-');
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[int.parse(parts[1])];
  }).toList();

  return SizedBox(
    height: 220,
    child: LineChart(
      LineChartData(
        minY: 0,
        maxY: maxVal * 1.2,
        gridData: FlGridData(
          show: true,
          horizontalInterval: maxVal > 0 ? (maxVal * 1.2 / 4) : 1,
          getDrawingHorizontalLine: (value) => FlLine(color: AppColors.divider, strokeWidth: 0.5),
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(labels[idx], style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                );
              },
              reservedSize: 24,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spotsIncome,
            isCurved: true,
            color: AppColors.success,
            barWidth: 2.5,
            dotData: FlDotData(show: spotsIncome.length < 8),
            belowBarData: BarAreaData(show: true, color: AppColors.success.withOpacity(0.1)),
          ),
          LineChartBarData(
            spots: spotsExpense,
            isCurved: true,
            color: AppColors.highlight,
            barWidth: 2.5,
            dotData: FlDotData(show: spotsExpense.length < 8),
            belowBarData: BarAreaData(show: true, color: AppColors.highlight.withOpacity(0.1)),
          ),
        ],
      ),
    ),
  );
}
