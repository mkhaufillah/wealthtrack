import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import 'package:wealthtrack/features/auth/models/token_model.dart';
import 'package:wealthtrack/features/transactions/models/transaction_model.dart';

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
}
