import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/providers/transaction_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/transactions/models/transaction_model.dart';
import 'package:wealthtrack/features/transactions/ui/transaction_list_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import '../helpers/mocks.dart';

/// Mock notifier that does NOT auto-load on init (screen's initState will call
/// load(), but we override it to be a no-op since we control state directly).
class _MockTxNotifier extends TransactionListNotifier {
  _MockTxNotifier() : super(TransactionRepository(MockApiClient()), MockApiClient());

  @override
  Future<void> load({bool refresh = false}) async {
    // no-op — state is set directly in tests
  }
}

final sampleTxn = TransactionModel(
  id: 1, amount: 50000, type: 'expense',
  description: 'Lunch', note: '', date: '2026-05-27',
  category: CategoryBrief(id: 3, name: 'Food', icon: '🍔'),
);

Widget buildTxListApp({
  bool isLoading = false,
  String? error,
  List<TransactionModel>? txns,
}) {
  return ProviderScope(
    overrides: [
      transactionListProvider.overrideWithProvider(
        StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
          final notifier = _MockTxNotifier();
          notifier.state = TransactionListState(
            isLoading: isLoading,
            error: error,
            transactions: txns ?? [],
            total: txns?.length ?? 0,
          );
          return notifier;
        }),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const TransactionListScreen(),
    ),
  );
}

void main() {
  group('TransactionListScreen', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      await tester.pumpWidget(buildTxListApp(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error display when error present', (tester) async {
      await tester.pumpWidget(buildTxListApp(error: 'Failed to load'));
      expect(find.text('Failed to load'), findsOneWidget);
    });

    testWidgets('shows empty state when no transactions', (tester) async {
      await tester.pumpWidget(buildTxListApp());
      expect(find.text('No transactions yet. Add one now!'), findsOneWidget);
    });

    testWidgets('shows transaction items in list', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('-Rp50.000'), findsOneWidget);
    });

    testWidgets('shows multiple transactions', (tester) async {
      final txn2 = TransactionModel(
        id: 2, amount: 100000, type: 'income',
        description: 'Freelance', note: '', date: '2026-05-26',
        category: CategoryBrief(id: 1, name: 'Salary', icon: '💰'),
      );
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn, txn2]));
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Freelance'), findsOneWidget);
      expect(find.text('+Rp100.000'), findsOneWidget);
    });
  });
}
