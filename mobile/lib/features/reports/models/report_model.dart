class CategoryBreakdown {
  final int categoryId;
  final String categoryName;
  final String icon;
  final int total;
  final int count;
  final double percentage;

  const CategoryBreakdown({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.total,
    required this.count,
    required this.percentage,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) =>
      CategoryBreakdown(
        categoryId: json['category_id'] ?? 0,
        categoryName: json['category_name'] ?? '',
        icon: json['icon'] ?? '',
        total: json['total'] ?? 0,
        count: json['count'] ?? 0,
        percentage: (json['percentage'] ?? 0).toDouble(),
      );
}

class UserBreakdown {
  final int userId;
  final String displayName;
  final int totalExpense;
  final int totalIncome;

  const UserBreakdown({
    required this.userId,
    required this.displayName,
    required this.totalExpense,
    this.totalIncome = 0,
  });

  factory UserBreakdown.fromJson(Map<String, dynamic> json) =>
      UserBreakdown(
        userId: json['user_id'] ?? 0,
        displayName: json['display_name'] ?? '',
        totalExpense: json['total_expense'] ?? 0,
        totalIncome: json['total_income'] ?? 0,
      );
}

class DailySnapshot {
  final String date;
  final int expense;
  final int income;

  const DailySnapshot({
    required this.date,
    required this.expense,
    required this.income,
  });

  factory DailySnapshot.fromJson(Map<String, dynamic> json) =>
      DailySnapshot(
        date: json['date'] ?? '',
        expense: json['expense'] ?? 0,
        income: json['income'] ?? 0,
      );
}

class MonthlyReport {
  final String month;
  final int totalIncome;
  final int totalExpense;
  final int balance;
  final List<CategoryBreakdown> categories;
  final List<DailySnapshot> dailySnapshot;

  const MonthlyReport({
    required this.month,
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    this.categories = const [],
    this.dailySnapshot = const [],
  });

  factory MonthlyReport.fromJson(Map<String, dynamic> json) =>
      MonthlyReport(
        month: json['month'] ?? '',
        totalIncome: json['total_income'] ?? 0,
        totalExpense: json['total_expense'] ?? 0,
        balance: json['balance'] ?? 0,
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) => CategoryBreakdown.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        dailySnapshot: (json['daily_snapshot'] as List<dynamic>?)
                ?.map((e) => DailySnapshot.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class HouseholdReport {
  final String dateFrom;
  final String dateTo;
  final int totalIncome;
  final int totalExpense;
  final int balance;
  final List<CategoryBreakdown> byCategory;
  final List<UserBreakdown> byUser;

  const HouseholdReport({
    required this.dateFrom,
    required this.dateTo,
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    this.byCategory = const [],
    this.byUser = const [],
  });

  factory HouseholdReport.fromJson(Map<String, dynamic> json) =>
      HouseholdReport(
        dateFrom: json['date_from'] ?? '',
        dateTo: json['date_to'] ?? '',
        totalIncome: json['total_income'] ?? 0,
        totalExpense: json['total_expense'] ?? 0,
        balance: json['balance'] ?? 0,
        byCategory: (json['by_category'] as List<dynamic>?)
                ?.map((e) => CategoryBreakdown.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        byUser: (json['by_user'] as List<dynamic>?)
                ?.map((e) => UserBreakdown.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}


class MonthlyTrend {
  final String month;
  final int totalIncome;
  final int totalExpense;
  final int balance;

  const MonthlyTrend({
    required this.month,
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
  });

  factory MonthlyTrend.fromJson(Map<String, dynamic> json) => MonthlyTrend(
        month: json['month'] ?? '',
        totalIncome: json['total_income'] ?? 0,
        totalExpense: json['total_expense'] ?? 0,
        balance: json['balance'] ?? 0,
      );
}
