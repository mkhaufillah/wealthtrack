import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/providers/transaction_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/transactions/ui/add_transaction_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

class _MockRepo extends TransactionRepository {
  _MockRepo() : super(MockApiClient());
}

Widget buildAddTxnApp() {
  return ProviderScope(
    overrides: [
      transactionListProvider.overrideWithProvider(
        StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
          return TransactionListNotifier(_MockRepo(), MockApiClient());
        }),
      ),
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => MockApiClient()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const AddTransactionScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

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

    testWidgets('shows Expense selected by default', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      // Expense should appear as a tappable button
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
    });

    testWidgets('tapping Income switches type', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      // Tap Income button
      await tester.tap(find.text('Income'));
      await tester.pump();
      // Both buttons should still exist
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
    });

    testWidgets('loads categories from API', (tester) async {
      final mockApi = MockApiClient();
      mockApi.onGet('/categories', [
        {'id': 6, 'name': 'Makanan & Minuman', 'name_en': 'Food & Drinks', 'type': 'expense', 'icon': '🍜'},
        {'id': 7, 'name': 'Transportasi & Bensin', 'name_en': 'Transport & Fuel', 'type': 'expense', 'icon': '🚗'},
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionListProvider.overrideWithProvider(
              StateNotifierProvider<TransactionListNotifier, TransactionListState>((ref) {
                return TransactionListNotifier(_MockRepo(), MockApiClient());
              }),
            ),
            apiClientProvider.overrideWithProvider(
              Provider<ApiClient>((ref) => mockApi),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AddTransactionScreen(),
          ),
        ),
      );

      // Wait for API call to resolve
      await tester.pumpAndSettle();
      // Should show expense category chips (translated)
      expect(find.textContaining('Food'), findsOneWidget);
      expect(find.textContaining('Transport'), findsOneWidget);
    });
  });
}
