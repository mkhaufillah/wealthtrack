import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/providers/transfer_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import '../helpers/mocks.dart';

void main() {
  group('TransferBalanceNotifier', () {
    late MockApiClient mockApi;
    late TransactionRepository repo;
    late TransferBalanceNotifier notifier;

    setUp(() {
      mockApi = MockApiClient();
      repo = TransactionRepository(mockApi);
      notifier = TransferBalanceNotifier(repo, mockApi);
    });

    test('initial state is correct', () {
      expect(notifier.state.isSubmitting, false);
      expect(notifier.state.error, isNull);
      expect(notifier.state.success, false);
      expect(notifier.state.transactionCount, 0);
    });

    test('reset returns to initial state', () {
      mockApi.onPost('/transactions/transfer', {
        'transactions': [
          {'id': 1, 'amount': 50000},
        ],
      });
      notifier.submit(
        date: '2025-01-15',
        transfers: [
          {'to_user_id': 2, 'amount': 50000},
        ],
      );
      // Reset
      notifier.reset();
      expect(notifier.state.isSubmitting, false);
      expect(notifier.state.error, isNull);
      expect(notifier.state.success, false);
      expect(notifier.state.transactionCount, 0);
    });

    test('submit sets isSubmitting true then success with transaction count',
        () async {
      mockApi.onPost('/transactions/transfer', {
        'transactions': [
          {'id': 1, 'amount': 50000, 'description': 'Transfer to Nahda'},
          {'id': 2, 'amount': -50000, 'description': 'Transfer from Filla'},
        ],
      });

      final result = await notifier.submit(
        date: '2025-01-15',
        transfers: [
          {'to_user_id': 2, 'amount': 50000},
        ],
      );

      expect(result, true);
      expect(notifier.state.isSubmitting, false);
      expect(notifier.state.success, true);
      expect(notifier.state.transactionCount, 2);
      expect(notifier.state.error, isNull);
    });

    test('submit sets error on failure', () async {
      // No mock set up → empty response, will fail parsing transactions list
      final result = await notifier.submit(
        date: '2025-01-15',
        transfers: [
          {'to_user_id': 2, 'amount': 50000},
        ],
      );

      expect(result, false);
      expect(notifier.state.isSubmitting, false);
      expect(notifier.state.success, false);
      expect(notifier.state.error, isNotNull);
    });

    test('getHouseholdMembers returns members on success', () async {
      mockApi.onGet('/households/me', {
        'members': [
          {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
          {'user_id': 3, 'display_name': 'Test', 'role': 'member'},
        ],
      });

      final members = await notifier.getHouseholdMembers();

      expect(members.length, 2);
      expect(members[0]['display_name'], 'Nahda');
      expect(members[1]['display_name'], 'Test');
    });

    test('getHouseholdMembers returns empty list on API error', () async {
      // No mock set up → empty response
      final members = await notifier.getHouseholdMembers();

      expect(members, isEmpty);
    });

    test('submit returns true on success', () async {
      mockApi.onPost('/transactions/transfer', {
        'transactions': [{'id': 1}],
      });

      final result = await notifier.submit(
        date: '2025-01-15',
        transfers: [{'to_user_id': 2, 'amount': 50000}],
      );

      expect(result, true);
      expect(notifier.state.success, true);
    });

    test('submit returns false on error', () async {
      final result = await notifier.submit(
        date: '2025-01-15',
        transfers: [{'to_user_id': 2, 'amount': 50000}],
      );

      expect(result, false);
    });
  });
}
