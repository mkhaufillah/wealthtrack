class BudgetModel {
  final int id;
  final String month;
  final int categoryId;
  final String categoryName;
  final String categoryIcon;
  final int amount;

  BudgetModel({
    required this.id,
    required this.month,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.amount,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) => BudgetModel(
        id: json['id'] as int,
        month: json['month'] as String,
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        amount: json['amount'] as int,
      );
}

class BudgetSummaryItem {
  final int id;
  final int categoryId;
  final String categoryName;
  final String categoryIcon;
  final int budgetAmount;
  final int actualSpent;
  final double percentage;
  final int remaining;
  final int cycleOn;

  BudgetSummaryItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.budgetAmount,
    required this.actualSpent,
    required this.percentage,
    required this.remaining,
    required this.cycleOn,
  });

  factory BudgetSummaryItem.fromJson(Map<String, dynamic> json) =>
      BudgetSummaryItem(
        id: json['id'] as int,
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        budgetAmount: json['budget_amount'] as int,
        actualSpent: json['actual_spent'] as int,
        percentage: (json['percentage'] as num).toDouble(),
        remaining: json['remaining'] as int,
        cycleOn: json['cycle_on'] as int? ?? 1,
      );
}
