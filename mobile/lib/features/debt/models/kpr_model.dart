class KPRScheduleItem {
  final int monthNumber;
  final int payment;
  final int principal;
  final int interest;
  final int remainingBalance;
  final String rateType;
  final double interestRate;

  KPRScheduleItem({
    required this.monthNumber,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.remainingBalance,
    required this.rateType,
    required this.interestRate,
  });

  factory KPRScheduleItem.fromJson(Map<String, dynamic> json) {
    return KPRScheduleItem(
      monthNumber: json['month_number'] as int,
      payment: json['payment'] as int,
      principal: json['principal'] as int,
      interest: json['interest'] as int,
      remainingBalance: json['remaining_balance'] as int,
      rateType: json['rate_type'] as String? ?? 'fixed',
      interestRate: (json['interest_rate'] as num).toDouble(),
    );
  }
}

class KPRSimulation {
  final int id;
  final int userId;
  final String name;
  final int propertyPrice;
  final int downPayment;
  final int totalLoan;
  final int tenorMonths;
  final String interestType;
  final String createdAt;
  final int totalInterest;
  final int monthlyPayment;
  final int startMonth;
  final int startYear;
  final int currentMonthNumber;
  final int currentMonthPayment;
  final int currentRemainingBalance;
  final List<KPRScheduleItem>? schedule;
  final Map<String, dynamic>? summary;

  KPRSimulation({
    required this.id,
    required this.userId,
    required this.name,
    required this.propertyPrice,
    required this.downPayment,
    required this.totalLoan,
    required this.tenorMonths,
    required this.interestType,
    required this.createdAt,
    this.totalInterest = 0,
    this.monthlyPayment = 0,
    this.startMonth = 1,
    this.startYear = 2026,
    this.currentMonthNumber = 1,
    this.currentMonthPayment = 0,
    this.currentRemainingBalance = 0,
    this.schedule,
    this.summary,
  });

  factory KPRSimulation.fromJson(Map<String, dynamic> json) {
    return KPRSimulation(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      name: json['name'] as String? ?? '',
      propertyPrice: json['property_price'] as int? ?? 0,
      downPayment: json['down_payment'] as int? ?? 0,
      totalLoan: json['total_loan'] as int? ?? 0,
      tenorMonths: json['tenor_months'] as int? ?? 0,
      interestType: json['interest_type'] as String? ?? 'fixed',
      createdAt: json['created_at'] as String? ?? '',
      totalInterest: json['total_interest'] as int? ?? 0,
      monthlyPayment: json['monthly_payment'] as int? ?? 0,
      startMonth: json['start_month'] as int? ?? 1,
      startYear: json['start_year'] as int? ?? DateTime.now().year,
      currentMonthNumber: json['current_month_number'] as int? ?? 1,
      currentMonthPayment: json['current_month_payment'] as int? ?? 0,
      currentRemainingBalance: json['current_remaining_balance'] as int? ?? 0,
      schedule: (json['schedule'] as List?)
          ?.map((e) => KPRScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: json['summary'] as Map<String, dynamic>?,
    );
  }
}

class KPRRatePeriod {
  final int periodStart;
  final int periodEnd;
  final double interestRate;
  final String rateType;

  KPRRatePeriod({
    required this.periodStart,
    required this.periodEnd,
    required this.interestRate,
    required this.rateType,
  });

  Map<String, dynamic> toJson() => {
        'period_start': periodStart,
        'period_end': periodEnd,
        'interest_rate': interestRate,
        'rate_type': rateType,
      };
}

class KPRCreateRequest {
  final String name;
  final int propertyPrice;
  final int downPayment;
  final int tenorMonths;
  final String interestType;
  final double baseInterestRate;
  final double graduatedIncrement;
  final int graduatedEveryMonths;
  final List<KPRRatePeriod> ratePeriods;

  KPRCreateRequest({
    required this.name,
    required this.propertyPrice,
    required this.downPayment,
    required this.tenorMonths,
    required this.interestType,
    this.baseInterestRate = 0.0,
    this.graduatedIncrement = 0.0,
    this.graduatedEveryMonths = 0,
    this.ratePeriods = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'property_price': propertyPrice,
        'down_payment': downPayment,
        'tenor_months': tenorMonths,
        'interest_type': interestType,
        'base_interest_rate': baseInterestRate,
        'graduated_increment': graduatedIncrement,
        'graduated_every_months': graduatedEveryMonths,
        if (ratePeriods.isNotEmpty)
          'rate_periods': ratePeriods.map((rp) => rp.toJson()).toList(),
      };
}
