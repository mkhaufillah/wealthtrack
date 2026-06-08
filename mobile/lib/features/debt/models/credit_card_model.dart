class CreditCardModel {
  final int id;
  final int userId;
  final String name;
  final String cardNumberLast4;
  final int billingDate;
  final int dueDate;
  final int creditLimit;
  final String createdAt;
  final int activeInstallments;
  final List<CCTransaction>? transactions;
  final List<CCInstallment>? installments;

  CreditCardModel({
    required this.id,
    required this.userId,
    required this.name,
    this.cardNumberLast4 = '',
    this.billingDate = 1,
    this.dueDate = 15,
    this.creditLimit = 0,
    required this.createdAt,
    this.activeInstallments = 0,
    this.transactions,
    this.installments,
  });

  factory CreditCardModel.fromJson(Map<String, dynamic> json) {
    return CreditCardModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      name: json['name'] as String? ?? '',
      cardNumberLast4: json['card_number_last4'] as String? ?? '',
      billingDate: json['billing_date'] as int? ?? 1,
      dueDate: json['due_date'] as int? ?? 15,
      creditLimit: json['credit_limit'] as int? ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      activeInstallments: json['active_installments'] as int? ?? 0,
      transactions: (json['transactions'] as List?)
          ?.map((e) => CCTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      installments: (json['installments'] as List?)
          ?.map((e) => CCInstallment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CCTransaction {
  final int id;
  final int cardId;
  final String description;
  final int amount;
  final int? categoryId;
  final String transactionDate;
  final bool isInstallment;
  final int? installmentId;
  final String createdAt;

  CCTransaction({
    required this.id,
    required this.cardId,
    required this.description,
    required this.amount,
    this.categoryId,
    required this.transactionDate,
    this.isInstallment = false,
    this.installmentId,
    required this.createdAt,
  });

  factory CCTransaction.fromJson(Map<String, dynamic> json) {
    return CCTransaction(
      id: json['id'] as int,
      cardId: json['card_id'] as int,
      description: json['description'] as String? ?? '',
      amount: json['amount'] as int,
      categoryId: json['category_id'] as int?,
      transactionDate: json['transaction_date'] as String? ?? '',
      isInstallment: (json['is_installment'] as int? ?? 0) == 1,
      installmentId: json['installment_id'] as int?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class CCInstallment {
  final int id;
  final int cardId;
  final String description;
  final int totalAmount;
  final int monthlyAmount;
  final int totalMonths;
  final int remainingMonths;
  final String startMonth;
  final String createdAt;

  CCInstallment({
    required this.id,
    required this.cardId,
    required this.description,
    required this.totalAmount,
    required this.monthlyAmount,
    required this.totalMonths,
    required this.remainingMonths,
    required this.startMonth,
    required this.createdAt,
  });

  factory CCInstallment.fromJson(Map<String, dynamic> json) {
    return CCInstallment(
      id: json['id'] as int,
      cardId: json['card_id'] as int,
      description: json['description'] as String? ?? '',
      totalAmount: json['total_amount'] as int,
      monthlyAmount: json['monthly_amount'] as int,
      totalMonths: json['total_months'] as int,
      remainingMonths: json['remaining_months'] as int,
      startMonth: json['start_month'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class NextMonthProjection {
  final int totalInstallments;
  final int totalExpected;
  final List<Map<String, dynamic>> perCard;

  NextMonthProjection({
    this.totalInstallments = 0,
    this.totalExpected = 0,
    this.perCard = const [],
  });

  factory NextMonthProjection.fromJson(Map<String, dynamic> json) {
    return NextMonthProjection(
      totalInstallments: json['total_installments'] as int? ?? 0,
      totalExpected: json['total_expected'] as int? ?? 0,
      perCard: (json['per_card'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }
}
