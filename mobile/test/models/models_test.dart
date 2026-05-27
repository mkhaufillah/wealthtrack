import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import 'package:wealthtrack/features/auth/models/token_model.dart';
import 'package:wealthtrack/features/transactions/models/transaction_model.dart';
import 'package:wealthtrack/features/reports/models/report_model.dart';

void main() {
  group('UserModel', () {
    test('fromJson creates correct instance', () {
      final json = {'id': 1, 'username': 'filla', 'display_name': 'Filla', 'role': 'user'};
      final user = UserModel.fromJson(json);
      expect(user.id, 1);
      expect(user.username, 'filla');
      expect(user.displayName, 'Filla');
      expect(user.role, 'user');
    });

    test('toJson produces correct map', () {
      final user = UserModel(id: 1, username: 'filla', displayName: 'Filla', role: 'user');
      final json = user.toJson();
      expect(json['id'], 1);
      expect(json['username'], 'filla');
      expect(json['display_name'], 'Filla');
      expect(json['role'], 'user');
    });
  });

  group('TokenModel', () {
    test('fromJson creates correct instance', () {
      final json = {'access_token': 'abc123', 'token_type': 'bearer', 'expires_in': 3600};
      final token = TokenModel.fromJson(json);
      expect(token.accessToken, 'abc123');
      expect(token.tokenType, 'bearer');
      expect(token.expiresIn, 3600);
    });
  });

  group('TransactionModel', () {
    test('fromJson creates instance with all fields', () {
      final json = {
        'id': 1, 'amount': 50000, 'type': 'expense',
        'description': 'Lunch', 'note': 'At resto', 'date': '2026-05-27',
        'category': {'id': 3, 'name': 'Food', 'icon': '🍔'},
      };
      final txn = TransactionModel.fromJson(json);
      expect(txn.id, 1);
      expect(txn.amount, 50000);
      expect(txn.type, 'expense');
      expect(txn.description, 'Lunch');
      expect(txn.note, 'At resto');
      expect(txn.date, '2026-05-27');
      expect(txn.category.id, 3);
      expect(txn.category.name, 'Food');
      expect(txn.category.icon, '🍔');
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': 2, 'amount': 100000, 'type': 'income',
        'description': null, 'note': null, 'date': null,
        'category': {'id': 1, 'name': 'Salary', 'icon': null},
      };
      final txn = TransactionModel.fromJson(json);
      expect(txn.description, '');
      expect(txn.note, '');
      expect(txn.date, '');
      expect(txn.category.icon, '');
    });

    test('CategoryBrief fromJson', () {
      final json = {'id': 5, 'name': 'Transport', 'icon': '🚗'};
      final cat = CategoryBrief.fromJson(json);
      expect(cat.id, 5);
      expect(cat.name, 'Transport');
      expect(cat.icon, '🚗');
    });
  });

  group('DailySnapshot', () {
    test('fromJson parses correctly', () {
      final json = {'date': '2026-05-27', 'expense': 50000, 'income': 100000};
      final ds = DailySnapshot.fromJson(json);
      expect(ds.date, '2026-05-27');
      expect(ds.expense, 50000);
      expect(ds.income, 100000);
    });
  });

  group('CategoryBreakdown', () {
    test('fromJson parses correctly', () {
      final json = {
        'category_id': 1, 'category_name': 'Food', 'icon': '🍽️',
        'total': 150000, 'count': 3, 'percentage': 25.5,
      };
      final cb = CategoryBreakdown.fromJson(json);
      expect(cb.categoryId, 1);
      expect(cb.categoryName, 'Food');
      expect(cb.icon, '🍽️');
      expect(cb.total, 150000);
      expect(cb.count, 3);
      expect(cb.percentage, 25.5);
    });
  });

  group('UserBreakdown', () {
    test('fromJson parses correctly', () {
      final json = {
        'user_id': 1, 'display_name': 'Filla',
        'total_expense': 500000, 'total_income': 1000000,
      };
      final ub = UserBreakdown.fromJson(json);
      expect(ub.userId, 1);
      expect(ub.displayName, 'Filla');
      expect(ub.totalExpense, 500000);
      expect(ub.totalIncome, 1000000);
    });
  });

  group('MonthlyReport', () {
    test('fromJson parses full report', () {
      final json = {
        'month': '2026-05',
        'total_income': 10000000,
        'total_expense': 4000000,
        'balance': 6000000,
        'categories': [
          {'category_id': 1, 'category_name': 'Food', 'icon': '🍽️', 'total': 2000000, 'count': 10, 'percentage': 50.0},
        ],
        'daily_snapshot': [
          {'date': '2026-05-27', 'expense': 50000, 'income': 0},
        ],
      };
      final mr = MonthlyReport.fromJson(json);
      expect(mr.month, '2026-05');
      expect(mr.totalIncome, 10000000);
      expect(mr.totalExpense, 4000000);
      expect(mr.balance, 6000000);
      expect(mr.categories.length, 1);
      expect(mr.categories[0].categoryName, 'Food');
      expect(mr.dailySnapshot.length, 1);
      expect(mr.dailySnapshot[0].date, '2026-05-27');
    });
  });

  group('HouseholdReport', () {
    test('fromJson parses with by_category and by_user', () {
      final json = {
        'date_from': '2026-05-01', 'date_to': '2026-05-31',
        'total_income': 15000000, 'total_expense': 8000000, 'balance': 7000000,
        'by_category': [
          {'category_id': 1, 'category_name': 'Food', 'icon': '🍽️', 'total': 3000000, 'count': 15, 'percentage': 37.5},
        ],
        'by_user': [
          {'user_id': 1, 'display_name': 'Filla', 'total_expense': 5000000, 'total_income': 10000000},
          {'user_id': 2, 'display_name': 'Nahda', 'total_expense': 3000000, 'total_income': 5000000},
        ],
      };
      final hr = HouseholdReport.fromJson(json);
      expect(hr.dateFrom, '2026-05-01');
      expect(hr.dateTo, '2026-05-31');
      expect(hr.totalIncome, 15000000);
      expect(hr.totalExpense, 8000000);
      expect(hr.balance, 7000000);
      expect(hr.byCategory.length, 1);
      expect(hr.byCategory[0].categoryName, 'Food');
      expect(hr.byUser.length, 2);
      expect(hr.byUser[0].displayName, 'Filla');
      expect(hr.byUser[1].displayName, 'Nahda');
    });
  });
}
