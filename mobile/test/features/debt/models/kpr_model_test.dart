import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/debt/models/kpr_model.dart';

void main() {
  group('KPRScheduleItem', () {
    test('fromJson creates correct instance', () {
      final json = {
        'month_number': 1,
        'payment': 5000000,
        'principal': 3000000,
        'interest': 2000000,
        'remaining_balance': 997000000,
        'rate_type': 'fixed',
        'interest_rate': 7.5,
      };
      final item = KPRScheduleItem.fromJson(json);
      expect(item.monthNumber, 1);
      expect(item.payment, 5000000);
      expect(item.principal, 3000000);
      expect(item.interest, 2000000);
      expect(item.remainingBalance, 997000000);
      expect(item.rateType, 'fixed');
      expect(item.interestRate, 7.5);
    });

    test('fromJson uses default rateType when null', () {
      final json = {
        'month_number': 1,
        'payment': 5000000,
        'principal': 3000000,
        'interest': 2000000,
        'remaining_balance': 997000000,
        'rate_type': null,
        'interest_rate': 7.5,
      };
      final item = KPRScheduleItem.fromJson(json);
      expect(item.rateType, 'fixed');
    });

    test('fromJson handles minimum required fields', () {
      final json = {
        'month_number': 1,
        'payment': 0,
        'principal': 0,
        'interest': 0,
        'remaining_balance': 0,
        'rate_type': 'floating',
        'interest_rate': 10.0,
      };
      final item = KPRScheduleItem.fromJson(json);
      expect(item.monthNumber, 1);
      expect(item.payment, 0);
      expect(item.principal, 0);
      expect(item.interest, 0);
      expect(item.remainingBalance, 0);
      expect(item.rateType, 'floating');
      expect(item.interestRate, 10.0);
    });
  });

  group('KPRSimulation', () {
    test('fromJson creates instance with all fields', () {
      final json = {
        'id': 1,
        'user_id': 1,
        'name': 'Rumah Impian',
        'property_price': 1000000000,
        'down_payment': 200000000,
        'total_loan': 800000000,
        'tenor_months': 120,
        'interest_type': 'fixed',
        'created_at': '2026-06-09T10:00:00Z',
        'total_interest': 300000000,
        'monthly_payment': 6666667,
        'start_month': 6,
        'start_year': 2026,
        'current_month_number': 1,
        'current_month_payment': 6666667,
        'current_remaining_balance': 793333333,
        'due_date': 10,
        'schedule': [
          {
            'month_number': 1,
            'payment': 6666667,
            'principal': 3000000,
            'interest': 3666667,
            'remaining_balance': 797000000,
            'rate_type': 'fixed',
            'interest_rate': 5.5,
          },
        ],
        'summary': {'total_payment': 1000000000},
      };
      final sim = KPRSimulation.fromJson(json);
      expect(sim.id, 1);
      expect(sim.userId, 1);
      expect(sim.name, 'Rumah Impian');
      expect(sim.propertyPrice, 1000000000);
      expect(sim.downPayment, 200000000);
      expect(sim.totalLoan, 800000000);
      expect(sim.tenorMonths, 120);
      expect(sim.interestType, 'fixed');
      expect(sim.createdAt, '2026-06-09T10:00:00Z');
      expect(sim.totalInterest, 300000000);
      expect(sim.monthlyPayment, 6666667);
      expect(sim.startMonth, 6);
      expect(sim.startYear, 2026);
      expect(sim.currentMonthNumber, 1);
      expect(sim.currentMonthPayment, 6666667);
      expect(sim.currentRemainingBalance, 793333333);
      expect(sim.dueDate, 10);
      expect(sim.schedule, isNotNull);
      expect(sim.schedule!.length, 1);
      expect(sim.schedule![0].monthNumber, 1);
      expect(sim.summary, isNotNull);
      expect(sim.summary!['total_payment'], 1000000000);
    });

    test('fromJson uses defaults for missing nullable fields', () {
      final json = {
        'id': 1,
        'user_id': 1,
        'name': null,
        'property_price': null,
        'down_payment': null,
        'total_loan': null,
        'tenor_months': null,
        'interest_type': null,
        'created_at': null,
      };
      final sim = KPRSimulation.fromJson(json);
      expect(sim.id, 1);
      expect(sim.userId, 1);
      expect(sim.name, '');
      expect(sim.propertyPrice, 0);
      expect(sim.downPayment, 0);
      expect(sim.totalLoan, 0);
      expect(sim.tenorMonths, 0);
      expect(sim.interestType, 'fixed');
      expect(sim.createdAt, '');
      expect(sim.totalInterest, 0);
      expect(sim.monthlyPayment, 0);
      expect(sim.startMonth, 1);
      expect(sim.startYear, DateTime.now().year);
      expect(sim.currentMonthNumber, 1);
      expect(sim.currentMonthPayment, 0);
      expect(sim.currentRemainingBalance, 0);
      expect(sim.dueDate, isNull);
      expect(sim.schedule, isNull);
      expect(sim.summary, isNull);
    });
  });

  group('KPRRatePeriod', () {
    test('toJson produces correct map', () {
      final period = KPRRatePeriod(
        periodStart: 1,
        periodEnd: 60,
        interestRate: 7.5,
        rateType: 'fixed',
      );
      final json = period.toJson();
      expect(json['period_start'], 1);
      expect(json['period_end'], 60);
      expect(json['interest_rate'], 7.5);
      expect(json['rate_type'], 'fixed');
    });

    test('toJson handles zero values', () {
      final period = KPRRatePeriod(
        periodStart: 0,
        periodEnd: 0,
        interestRate: 0.0,
        rateType: '',
      );
      final json = period.toJson();
      expect(json['period_start'], 0);
      expect(json['period_end'], 0);
      expect(json['interest_rate'], 0.0);
      expect(json['rate_type'], '');
    });
  });

  group('KPRCreateRequest', () {
    test('toJson produces correct map without ratePeriods', () {
      final request = KPRCreateRequest(
        name: 'Rumah Baru',
        propertyPrice: 1000000000,
        downPayment: 200000000,
        tenorMonths: 120,
        interestType: 'fixed',
        baseInterestRate: 7.5,
        graduatedIncrement: 1.0,
        graduatedEveryMonths: 12,
      );
      final json = request.toJson();
      expect(json['name'], 'Rumah Baru');
      expect(json['property_price'], 1000000000);
      expect(json['down_payment'], 200000000);
      expect(json['tenor_months'], 120);
      expect(json['interest_type'], 'fixed');
      expect(json['base_interest_rate'], 7.5);
      expect(json['graduated_increment'], 1.0);
      expect(json['graduated_every_months'], 12);
      expect(json.containsKey('rate_periods'), false);
    });

    test('toJson omits ratePeriods when empty', () {
      final request = KPRCreateRequest(
        name: 'Empty Periods',
        propertyPrice: 500000000,
        downPayment: 100000000,
        tenorMonths: 60,
        interestType: 'graduated',
        ratePeriods: [],
      );
      final json = request.toJson();
      expect(json.containsKey('rate_periods'), false);
    });

    test('toJson includes ratePeriods when non-empty', () {
      final request = KPRCreateRequest(
        name: 'With Periods',
        propertyPrice: 1000000000,
        downPayment: 200000000,
        tenorMonths: 120,
        interestType: 'graduated',
        baseInterestRate: 5.0,
        ratePeriods: [
          KPRRatePeriod(
            periodStart: 1,
            periodEnd: 12,
            interestRate: 5.0,
            rateType: 'promo',
          ),
          KPRRatePeriod(
            periodStart: 13,
            periodEnd: 24,
            interestRate: 6.0,
            rateType: 'fixed',
          ),
        ],
      );
      final json = request.toJson();
      expect(json['rate_periods'], isA<List>());
      expect((json['rate_periods'] as List).length, 2);
      expect(json['rate_periods'][0]['period_start'], 1);
      expect(json['rate_periods'][0]['rate_type'], 'promo');
      expect(json['rate_periods'][1]['period_start'], 13);
      expect(json['rate_periods'][1]['interest_rate'], 6.0);
    });
  });
}
