import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/ui/widgets/transaction_tile.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

Widget wrap(Widget w) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: w));

void main() {
  final expense = <String, dynamic>{
    'type': 'expense', 'amount': 50000,
    'description': 'Lunch at Sate Padang', 'date': '2026-05-27',
    'category': {'id': 3, 'name': 'Food', 'icon': '🍔'},
  };
  final income = <String, dynamic>{
    'type': 'income', 'amount': 3000000,
    'description': '', 'date': '2026-05-26',
    'category': {'id': 1, 'name': 'Salary', 'icon': '💰'},
  };

  group('TransactionTile', () {
    testWidgets('shows expense amount with minus sign', (tester) async {
      await tester.pumpWidget(wrap(TransactionTile(data: expense)));
      expect(find.text('-Rp50.000'), findsOneWidget);
    });

    testWidgets('shows income amount with plus sign', (tester) async {
      await tester.pumpWidget(wrap(TransactionTile(data: income)));
      expect(find.text('+Rp3.000.000'), findsOneWidget);
    });

    testWidgets('shows description as title when present', (tester) async {
      await tester.pumpWidget(wrap(TransactionTile(data: expense)));
      expect(find.text('Lunch at Sate Padang'), findsOneWidget);
    });

    testWidgets('falls back to category name when description empty', (tester) async {
      await tester.pumpWidget(wrap(TransactionTile(data: income)));
      expect(find.text('Salary'), findsOneWidget);
    });

    testWidgets('shows category icon', (tester) async {
      await tester.pumpWidget(wrap(TransactionTile(data: expense)));
      expect(find.text('🍔'), findsOneWidget);
    });

    testWidgets('shows fallback icon when category icon is null', (tester) async {
      final noIcon = <String, dynamic>{
        'type': 'expense', 'amount': 10000, 'description': 'Test',
        'date': '2026-05-27', 'category': {'id': 9, 'name': 'Other', 'icon': null},
      };
      await tester.pumpWidget(wrap(TransactionTile(data: noIcon)));
      expect(find.text('📦'), findsOneWidget);
    });
  });
}
