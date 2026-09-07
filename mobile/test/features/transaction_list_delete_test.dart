import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:wealthtrack/core/ui/app_icons.dart';
import 'package:wealthtrack/features/transactions/providers/transaction_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/transactions/models/transaction_model.dart';
import 'package:wealthtrack/features/transactions/ui/transaction_list_screen.dart';
import 'package:wealthtrack/features/ocr/providers/ocr_provider.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import '../helpers/mocks.dart';

/// Mock notifier that does NOT auto-load on init.
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
  final mockApi = MockApiClient();
  return ProviderScope(
    overrides: [
      ocrPendingCountProvider.overrideWithProvider(
        StateNotifierProvider<OcrPendingCountNotifier, OcrState>((ref) {
          return OcrPendingCountNotifier(mockApi, MockSecureStorage());
        }),
      ),
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
  setUp(() => initTestSecureStorage());

  group('TransactionListScreen — Delete', () {
    testWidgets('shows popup menu button on transaction tile', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical), findsOneWidget);
    });

    testWidgets('shows Delete option in popup menu', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('shows Edit option in popup menu', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('shows Change Owner option in popup menu', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();
      expect(find.text('Change Owner'), findsOneWidget);
    });

    testWidgets('tapping Delete shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));

      // Open popup menu
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();

      // Tap Delete
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Hapus transaksi?'), findsOneWidget);
      expect(find.textContaining('Lunch'), findsAtLeast(1));
      expect(find.text('Batal'), findsOneWidget);
    });

    testWidgets('tapping Cancel closes delete dialog', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));

      // Open popup menu
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();

      // Tap Delete
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Hapus transaksi?'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(find.text('Hapus transaksi?'), findsNothing);
    });

    testWidgets('delete dialog shows warning about undo', (tester) async {
      await tester.pumpWidget(buildTxListApp(txns: [sampleTxn]));

      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedMoreVertical));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gak bisa dibalikin'), findsOneWidget);
    });
  });
}
