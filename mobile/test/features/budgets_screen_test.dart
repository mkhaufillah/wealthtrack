import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/budgets/ui/budgets_screen.dart';
import 'package:wealthtrack/features/budgets/providers/budget_provider.dart';
import 'package:wealthtrack/features/budgets/data/budget_repository.dart';
import 'package:wealthtrack/features/budgets/models/budget_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

class _MockBudgetRepo extends BudgetRepository {
  _MockBudgetRepo() : super(MockApiClient());
}

Widget buildBudgetsApp({
  bool isLoading = false,
  String? error,
  List<BudgetSummaryItem> items = const [],
}) {
  return ProviderScope(
    overrides: [
      budgetProvider.overrideWithProvider(
        StateNotifierProvider<BudgetNotifier, BudgetState>((ref) {
          final notifier = BudgetNotifier(_MockBudgetRepo());
          notifier.state = BudgetState(
            isLoading: isLoading,
            error: error,
            items: items,
          );
          return notifier;
        }),
      ),
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => MockApiClient()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const BudgetsScreen(),
    ),
  );
}

final sampleItem = BudgetSummaryItem(
  categoryId: 1,
  categoryName: 'Makanan & Minuman',
  categoryIcon: '🍔',
  budgetAmount: 3000000,
  actualSpent: 1500000,
  percentage: 50.0,
  remaining: 1500000,
);

final overBudgetItem = BudgetSummaryItem(
  categoryId: 2,
  categoryName: 'Transportasi & Bensin',
  categoryIcon: '🚗',
  budgetAmount: 1000000,
  actualSpent: 1200000,
  percentage: 120.0,
  remaining: 0,
);

final warningItem = BudgetSummaryItem(
  categoryId: 3,
  categoryName: 'Belanja Harian',
  categoryIcon: '🛍️',
  budgetAmount: 2000000,
  actualSpent: 1600000,
  percentage: 80.0,
  remaining: 400000,
);

void main() {
  setUp(() => initTestSecureStorage());

  group('BudgetsScreen', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error display when error present', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(error: 'Failed to load budgets'));
      expect(find.text('Failed to load budgets'), findsOneWidget);
    });

    testWidgets('shows empty state when no budgets', (tester) async {
      await tester.pumpWidget(buildBudgetsApp());
      expect(find.text('No budgets set for this month'), findsOneWidget);
      expect(find.text('Tap + to add a spending limit per category'),
          findsOneWidget);
    });

    testWidgets('shows budget items in list', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [sampleItem]));
      expect(find.text('Food & Drinks'), findsOneWidget);
      expect(find.textContaining('Rp1.500.000'), findsAtLeast(1));
    });

    testWidgets('shows percentage for budget item', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [sampleItem]));
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('shows remaining amount for budget item', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [sampleItem]));
      expect(find.textContaining('remaining'), findsOneWidget);
      expect(find.textContaining('Rp1.500.000'), findsAtLeast(1));
    });

    testWidgets('shows over-budget warning for exceeded budgets',
        (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [overBudgetItem]));
      expect(find.text('Transport & Fuel'), findsOneWidget);
      expect(find.textContaining('Over by'), findsOneWidget);
      expect(find.textContaining('Rp200.000'), findsOneWidget);
    });

    testWidgets('shows multiple budget items', (tester) async {
      await tester.pumpWidget(
          buildBudgetsApp(items: [sampleItem, overBudgetItem, warningItem]));
      expect(find.text('Food & Drinks'), findsOneWidget);
      expect(find.text('Transport & Fuel'), findsOneWidget);
      expect(find.text('Daily Shopping'), findsOneWidget);
    });

    testWidgets('shows FAB to add budget', (tester) async {
      await tester.pumpWidget(buildBudgetsApp());
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows month picker with navigation arrows', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [sampleItem]));
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows progress bar for budget', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(items: [sampleItem]));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
