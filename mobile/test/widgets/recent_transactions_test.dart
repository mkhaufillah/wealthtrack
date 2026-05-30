import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/ui/widgets/recent_transactions.dart';
import 'package:wealthtrack/features/transactions/models/transaction_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

Widget wrap(Widget w) => MaterialApp(theme: AppTheme.light, home: w);

void main() {
  group('RecentTransactions', () {
    testWidgets('shows header', (tester) async {
      await tester.pumpWidget(wrap(const RecentTransactions(transactions: [])));
      expect(find.text('Recent Transactions'), findsOneWidget);
    });

    testWidgets('shows empty message when no transactions', (tester) async {
      await tester.pumpWidget(wrap(const RecentTransactions(transactions: [])));
      expect(find.text('No transactions this month'), findsOneWidget);
    });

    testWidgets('displays transaction tiles when data exists', (tester) async {
      final txns = [
        TransactionModel(
          id: 1, type: 'expense', amount: 50000,
          description: 'Coffee', note: '',
          date: '2026-05-27',
          category: CategoryBrief(id: 3, name: 'Food', nameEn: 'Food & Drinks', icon: '☕'),
        ),
        TransactionModel(
          id: 2, type: 'income', amount: 5000000,
          description: 'Gaji', note: '',
          date: '2026-05-01',
          category: CategoryBrief(id: 1, name: 'Salary', nameEn: 'Salary', icon: '💰'),
        ),
      ];
      await tester.pumpWidget(wrap(RecentTransactions(transactions: txns)));
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Gaji'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
    });
  });
}
