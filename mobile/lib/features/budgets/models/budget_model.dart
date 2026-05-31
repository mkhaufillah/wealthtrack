class BudgetModel {
  final int id;
  final String month;
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
  final String categoryIcon;
  final int amount;

  BudgetModel({
    required this.id,
    required this.month,
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameEn,
    required this.categoryIcon,
    required this.amount,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) => BudgetModel(
        id: json['id'] as int,
        month: json['month'] as String,
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryNameEn: json['category_name_en'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        amount: json['amount'] as int,
      );
}

class BudgetSummaryItem {
  final int id;
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
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
    required this.categoryNameEn,
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
        categoryNameEn: json['category_name_en'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        budgetAmount: json['budget_amount'] as int,
        actualSpent: json['actual_spent'] as int,
        percentage: (json['percentage'] as num).toDouble(),
        remaining: json['remaining'] as int,
        cycleOn: json['cycle_on'] as int? ?? 1,
      );
}

class UnbudgetedExpense {
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
  final String categoryIcon;
  final int total;

  UnbudgetedExpense({
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameEn,
    required this.categoryIcon,
    required this.total,
  });

  factory UnbudgetedExpense.fromJson(Map<String, dynamic> json) =>
      UnbudgetedExpense(
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryNameEn: json['category_name_en'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        total: json['total'] as int,
      );
}

class BudgetSuggestion {
  final int categoryId;
  final String categoryName;
  final String categoryNameEn;
  final String categoryIcon;
  final int suggestedAmount;
  final int historicalAvg;
  final int historicalMax;
  final int monthsAnalyzed;
  final bool hasBudget;
  final int existingAmount;
  bool accepted; // UI state: user toggle

  BudgetSuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.categoryNameEn,
    required this.categoryIcon,
    required this.suggestedAmount,
    required this.historicalAvg,
    required this.historicalMax,
    required this.monthsAnalyzed,
    this.hasBudget = false,
    this.existingAmount = 0,
    this.accepted = false,
  });

  BudgetSuggestion copyWith({bool? accepted, bool? hasBudget}) =>
      BudgetSuggestion(
        categoryId: categoryId,
        categoryName: categoryName,
        categoryNameEn: categoryNameEn,
        categoryIcon: categoryIcon,
        suggestedAmount: suggestedAmount,
        historicalAvg: historicalAvg,
        historicalMax: historicalMax,
        monthsAnalyzed: monthsAnalyzed,
        hasBudget: hasBudget ?? this.hasBudget,
        existingAmount: existingAmount,
        accepted: accepted ?? this.accepted,
      );

  factory BudgetSuggestion.fromJson(Map<String, dynamic> json) =>
      BudgetSuggestion(
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String? ?? '',
        categoryNameEn: json['category_name_en'] as String? ?? '',
        categoryIcon: json['category_icon'] as String? ?? '📦',
        suggestedAmount: json['suggested_amount'] as int,
        historicalAvg: json['historical_avg'] as int,
        historicalMax: json['historical_max'] as int,
        monthsAnalyzed: json['months_analyzed'] as int,
        hasBudget: json['has_budget'] as bool? ?? false,
        existingAmount: json['existing_amount'] as int? ?? 0,
      );
}

class BudgetSuggestionResponse {
  final List<BudgetSuggestion> items;
  final int totalSuggested;
  final int totalIncome;
  final String warning;

  BudgetSuggestionResponse(this.items, this.totalSuggested, this.totalIncome, this.warning);

  factory BudgetSuggestionResponse.fromJson(Map<String, dynamic> json) =>
      BudgetSuggestionResponse(
        (json['items'] as List)
            .map((e) => BudgetSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        json['total_suggested'] as int? ?? 0,
        json['total_income'] as int? ?? 0,
        json['warning'] as String? ?? '',
      );
}
