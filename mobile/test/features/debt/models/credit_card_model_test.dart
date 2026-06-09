import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/debt/models/credit_card_model.dart';

void main() {
  group('CreditCardModel', () {
    test('fromJson creates instance with all fields', () {
      final json = {
        'id': 1,
        'user_id': 1,
        'name': 'BCA Card',
        'card_number_last4': '1234',
        'billing_date': 5,
        'due_date': 15,
        'credit_limit': 10000000,
        'created_at': '2026-06-01T00:00:00Z',
        'active_installments': 2,
        'transactions': [
          {
            'id': 1,
            'card_id': 1,
            'description': 'Belanja',
            'amount': 500000,
            'category_id': 3,
            'transaction_date': '2026-06-10',
            'is_installment': 0,
            'installment_id': null,
            'created_at': '2026-06-10T12:00:00Z',
          },
        ],
        'installments': [
          {
            'id': 1,
            'card_id': 1,
            'description': 'Laptop',
            'total_amount': 12000000,
            'monthly_amount': 1000000,
            'total_months': 12,
            'remaining_months': 10,
            'start_month': '2026-01',
            'created_at': '2026-01-15T00:00:00Z',
          },
        ],
      };
      final card = CreditCardModel.fromJson(json);
      expect(card.id, 1);
      expect(card.userId, 1);
      expect(card.name, 'BCA Card');
      expect(card.cardNumberLast4, '1234');
      expect(card.billingDate, 5);
      expect(card.dueDate, 15);
      expect(card.creditLimit, 10000000);
      expect(card.createdAt, '2026-06-01T00:00:00Z');
      expect(card.activeInstallments, 2);
      expect(card.transactions, isNotNull);
      expect(card.transactions!.length, 1);
      expect(card.transactions![0].description, 'Belanja');
      expect(card.installments, isNotNull);
      expect(card.installments!.length, 1);
      expect(card.installments![0].description, 'Laptop');
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'id': 2,
        'user_id': 1,
        'name': null,
        'created_at': null,
      };
      final card = CreditCardModel.fromJson(json);
      expect(card.id, 2);
      expect(card.userId, 1);
      expect(card.name, '');
      expect(card.cardNumberLast4, '');
      expect(card.billingDate, 1);
      expect(card.dueDate, 15);
      expect(card.creditLimit, 0);
      expect(card.createdAt, '');
      expect(card.activeInstallments, 0);
      expect(card.transactions, isNull);
      expect(card.installments, isNull);
    });

    test('fromJson handles missing nested lists', () {
      final json = {
        'id': 3,
        'user_id': 1,
        'name': 'Mandiri Card',
        'created_at': '2026-06-01T00:00:00Z',
      };
      final card = CreditCardModel.fromJson(json);
      expect(card.transactions, isNull);
      expect(card.installments, isNull);
    });
  });

  group('CCTransaction', () {
    test('fromJson creates correct instance with all fields', () {
      final json = {
        'id': 1,
        'card_id': 1,
        'description': 'Makan Siang',
        'amount': 50000,
        'category_id': 3,
        'transaction_date': '2026-06-10',
        'is_installment': 0,
        'installment_id': null,
        'created_at': '2026-06-10T12:00:00Z',
      };
      final txn = CCTransaction.fromJson(json);
      expect(txn.id, 1);
      expect(txn.cardId, 1);
      expect(txn.description, 'Makan Siang');
      expect(txn.amount, 50000);
      expect(txn.categoryId, 3);
      expect(txn.transactionDate, '2026-06-10');
      expect(txn.isInstallment, false);
      expect(txn.installmentId, isNull);
      expect(txn.createdAt, '2026-06-10T12:00:00Z');
    });

    test('fromJson treats is_installment=1 as true', () {
      final json = {
        'id': 2,
        'card_id': 1,
        'description': 'Cicilan Laptop',
        'amount': 1000000,
        'transaction_date': '2026-06-10',
        'is_installment': 1,
        'installment_id': 10,
        'created_at': '2026-06-10T12:00:00Z',
      };
      final txn = CCTransaction.fromJson(json);
      expect(txn.isInstallment, true);
      expect(txn.installmentId, 10);
    });

    test('fromJson treats is_installment=null as false', () {
      final json = {
        'id': 3,
        'card_id': 1,
        'description': 'Regular',
        'amount': 25000,
        'transaction_date': '2026-06-10',
        'is_installment': null,
        'created_at': '2026-06-10T12:00:00Z',
      };
      final txn = CCTransaction.fromJson(json);
      expect(txn.isInstallment, false);
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': 4,
        'card_id': 2,
        'description': null,
        'amount': 75000,
        'transaction_date': null,
        'is_installment': 0,
        'created_at': null,
      };
      final txn = CCTransaction.fromJson(json);
      expect(txn.description, '');
      expect(txn.categoryId, isNull);
      expect(txn.transactionDate, '');
      expect(txn.installmentId, isNull);
      expect(txn.createdAt, '');
    });
  });

  group('CCInstallment', () {
    test('fromJson creates correct instance with all fields', () {
      final json = {
        'id': 1,
        'card_id': 1,
        'description': 'Laptop',
        'total_amount': 12000000,
        'monthly_amount': 1000000,
        'total_months': 12,
        'remaining_months': 10,
        'start_month': '2026-01',
        'created_at': '2026-01-15T00:00:00Z',
      };
      final inst = CCInstallment.fromJson(json);
      expect(inst.id, 1);
      expect(inst.cardId, 1);
      expect(inst.description, 'Laptop');
      expect(inst.totalAmount, 12000000);
      expect(inst.monthlyAmount, 1000000);
      expect(inst.totalMonths, 12);
      expect(inst.remainingMonths, 10);
      expect(inst.startMonth, '2026-01');
      expect(inst.createdAt, '2026-01-15T00:00:00Z');
    });

    test('fromJson handles null string fields', () {
      final json = {
        'id': 2,
        'card_id': 1,
        'description': null,
        'total_amount': 6000000,
        'monthly_amount': 500000,
        'total_months': 12,
        'remaining_months': 6,
        'start_month': null,
        'created_at': null,
      };
      final inst = CCInstallment.fromJson(json);
      expect(inst.description, '');
      expect(inst.startMonth, '');
      expect(inst.createdAt, '');
    });

    test('fromJson handles zero amounts', () {
      final json = {
        'id': 3,
        'card_id': 1,
        'description': 'Free Cicilan',
        'total_amount': 0,
        'monthly_amount': 0,
        'total_months': 0,
        'remaining_months': 0,
        'start_month': '2026-03',
        'created_at': '2026-03-01T00:00:00Z',
      };
      final inst = CCInstallment.fromJson(json);
      expect(inst.totalAmount, 0);
      expect(inst.monthlyAmount, 0);
      expect(inst.totalMonths, 0);
      expect(inst.remainingMonths, 0);
    });
  });

  group('NextMonthProjection', () {
    test('fromJson creates correct instance with perCard data', () {
      final json = {
        'total_installments': 500000,
        'total_expected': 3000000,
        'per_card': [
          {'card_id': 1, 'card_name': 'BCA', 'amount': 500000},
          {'card_id': 2, 'card_name': 'Mandiri', 'amount': 2500000},
        ],
      };
      final proj = NextMonthProjection.fromJson(json);
      expect(proj.totalInstallments, 500000);
      expect(proj.totalExpected, 3000000);
      expect(proj.perCard.length, 2);
      expect(proj.perCard[0]['card_name'], 'BCA');
      expect(proj.perCard[1]['amount'], 2500000);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};
      final proj = NextMonthProjection.fromJson(json);
      expect(proj.totalInstallments, 0);
      expect(proj.totalExpected, 0);
      expect(proj.perCard, isEmpty);
    });

    test('fromJson handles null perCard field', () {
      final json = {
        'total_installments': 1000000,
        'total_expected': 5000000,
        'per_card': null,
      };
      final proj = NextMonthProjection.fromJson(json);
      expect(proj.totalInstallments, 1000000);
      expect(proj.totalExpected, 5000000);
      expect(proj.perCard, isEmpty);
    });
  });
}
