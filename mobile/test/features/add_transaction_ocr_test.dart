import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:wealthtrack/core/ui/app_icons.dart';
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
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01), findsOneWidget);
    });

    testWidgets('tapping scan button shows source picker bottom sheet',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      // Bottom sheet should show
      expect(find.text('Ambil struk'), findsOneWidget);
      expect(find.text('Kamera atau dari galeri'), findsOneWidget);
    });

    testWidgets('bottom sheet shows Take Photo option', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      expect(find.text('Fotoin struk'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01), findsAtLeast(1));
    });

    testWidgets('bottom sheet shows Choose from Gallery option',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      expect(find.text('Ambil dari galeri'), findsOneWidget);
    });

    testWidgets('bottom sheet has gallery icon', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedImage01), findsOneWidget);
    });

    testWidgets('tapping Take Photo closes bottom sheet', (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fotoin struk'));
      await tester.pumpAndSettle();

      // Bottom sheet should close (Scan Receipt title gone)
      expect(find.text('Ambil struk'), findsNothing);
    });

    testWidgets('tapping Choose from Gallery closes bottom sheet',
        (tester) async {
      await tester.pumpWidget(buildAddTxnApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedCamera01));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ambil dari galeri'));
      await tester.pumpAndSettle();

      // Bottom sheet should close
      expect(find.text('Ambil struk'), findsNothing);
    });
  });
}
