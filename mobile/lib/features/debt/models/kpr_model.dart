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
  final int? dueDate;
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
    this.dueDate,
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
      dueDate: json['due_date'] as int?,
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


class ExtraPaymentOption {
  final int newInstallment;
  final int newTenor;
  final int totalInterestPaid;
  final int interestSaved;
  final String endDate;

  ExtraPaymentOption({
    required this.newInstallment,
    required this.newTenor,
    required this.totalInterestPaid,
    required this.interestSaved,
    required this.endDate,
  });

  factory ExtraPaymentOption.fromJson(Map<String, dynamic> json) {
    return ExtraPaymentOption(
      newInstallment: json['new_installment'] as int,
      newTenor: json['new_tenor'] as int,
      totalInterestPaid: json['total_interest_paid'] as int,
      interestSaved: json['interest_saved'] as int,
      endDate: json['end_date'] as String? ?? '',
    );
  }
}


class ExtraPaymentPreview {
  final ExtraPaymentOption optionInstallment;
  final ExtraPaymentOption optionTenor;
  final Map<String, dynamic> comparison;

  ExtraPaymentPreview({
    required this.optionInstallment,
    required this.optionTenor,
    required this.comparison,
  });

  factory ExtraPaymentPreview.fromJson(Map<String, dynamic> json) {
    return ExtraPaymentPreview(
      optionInstallment: ExtraPaymentOption.fromJson(
          json['option_installment'] as Map<String, dynamic>),
      optionTenor: ExtraPaymentOption.fromJson(
          json['option_tenor'] as Map<String, dynamic>),
      comparison: json['comparison'] as Map<String, dynamic>? ?? {},
    );
  }
}


class ExtraPaymentRecord {
  final int id;
  final int simulationId;
  final int amount;
  final int applyMonth;
  final String reductionType;
  final int oldRemainingBalance;
  final int newRemainingBalance;
  final int oldRemainingMonths;
  final int newRemainingMonths;
  final int oldInstallment;
  final int newInstallment;
  final int totalInterestSaving;
  final String originalEndDate;
  final String newEndDate;
  final String createdAt;

  ExtraPaymentRecord({
    required this.id,
    required this.simulationId,
    required this.amount,
    required this.applyMonth,
    required this.reductionType,
    required this.oldRemainingBalance,
    required this.newRemainingBalance,
    required this.oldRemainingMonths,
    required this.newRemainingMonths,
    required this.oldInstallment,
    required this.newInstallment,
    required this.totalInterestSaving,
    required this.originalEndDate,
    required this.newEndDate,
    required this.createdAt,
  });

  factory ExtraPaymentRecord.fromJson(Map<String, dynamic> json) {
    return ExtraPaymentRecord(
      id: json['id'] as int,
      simulationId: json['simulation_id'] as int,
      amount: json['amount'] as int,
      applyMonth: json['apply_month'] as int,
      reductionType: json['reduction_type'] as String? ?? 'tenor',
      oldRemainingBalance: json['old_remaining_balance'] as int,
      newRemainingBalance: json['new_remaining_balance'] as int,
      oldRemainingMonths: json['old_remaining_months'] as int,
      newRemainingMonths: json['new_remaining_months'] as int,
      oldInstallment: json['old_installment'] as int? ?? 0,
      newInstallment: json['new_installment'] as int? ?? 0,
      totalInterestSaving: json['total_interest_saved'] as int? ?? 0,
      originalEndDate: json['original_end_date'] as String? ?? '',
      newEndDate: json['new_end_date'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
