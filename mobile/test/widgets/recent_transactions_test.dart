import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/ui/widgets/recent_transactions.dart';
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
        <String, dynamic>{
          'type': 'expense', 'amount': 50000, 'description': 'Coffee',
          'date': '2026-05-27', 'category': {'id': 3, 'name': 'Food', 'icon': '☕'},
        },
        <String, dynamic>{
          'type': 'income', 'amount': 5000000, 'description': 'Gaji',
          'date': '2026-05-01', 'category': {'id': 1, 'name': 'Salary', 'icon': '💰'},
        },
      ];
      await tester.pumpWidget(wrap(RecentTransactions(transactions: txns)));
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Gaji'), findsOneWidget);
      // View All button should appear
      expect(find.text('View All'), findsOneWidget);
    });
  });
}
