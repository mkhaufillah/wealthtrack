import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/providers/transaction_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/transactions/ui/add_transaction_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

class _MockRepo extends TransactionRepository {
  _MockRepo() : super(null!);
}

Widget buildAddTxnApp() {
  return ProviderScope(
    overrides: [
      transactionListProvider.overrideWithProvider(
        StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
          return TransactionListNotifier(_MockRepo());
        }),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const AddTransactionScreen(),
    ),
  );
}

void main() {
  group('AddTransactionScreen', () {
    testWidgets('shows Add Transaction title', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Add Transaction'), findsOneWidget);
    });

    testWidgets('shows type toggle buttons', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
    });

    testWidgets('shows amount field', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.byType(TextField), findsAtLeast(1));
    });

    testWidgets('shows category section', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Category'), findsOneWidget);
    });

    testWidgets('shows description field', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Description'), findsOneWidget);
    });

    testWidgets('shows date picker', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Date'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows note section', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Note (optional)'), findsOneWidget);
      expect(find.text('Add a note...'), findsOneWidget);
    });

    testWidgets('shows Save button', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.text('Save'), findsOneWidget);
    });
  });
}
