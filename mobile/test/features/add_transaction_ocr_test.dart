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

  group('AddTransactionScreen — OCR / Scanner', () {
    testWidgets('shows scan button in app bar', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    });

    testWidgets('tapping scan button shows source picker bottom sheet',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      // Bottom sheet should show
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.text('Choose an image source'), findsOneWidget);
    });

    testWidgets('bottom sheet shows Take Photo option', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsAtLeast(1));
    });

    testWidgets('bottom sheet shows Choose from Gallery option',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('bottom sheet has gallery icon', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    });

    testWidgets('tapping Take Photo closes bottom sheet', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();

      // Bottom sheet should close (Scan Receipt title gone)
      expect(find.text('Scan Receipt'), findsNothing);
    });

    testWidgets('tapping Choose from Gallery closes bottom sheet',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();

      // Bottom sheet should close
      expect(find.text('Scan Receipt'), findsNothing);
    });
  });
}
