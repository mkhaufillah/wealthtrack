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
          final notifier = BudgetNotifier(_MockBudgetRepo(), MockApiClient());
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
  id: 1,
  categoryId: 1,
  categoryName: 'Makanan & Minuman',
  categoryNameEn: 'Food & Drinks',
  categoryIcon: '🍔',
  budgetAmount: 3000000,
  actualSpent: 1500000,
  percentage: 50.0,
  remaining: 1500000,
  cycleOn: 1,
);

final overBudgetItem = BudgetSummaryItem(
  id: 2,
  categoryId: 2,
  categoryName: 'Transportasi & Bensin',
  categoryNameEn: 'Transport & Fuel',
  categoryIcon: '🚗',
  budgetAmount: 1000000,
  actualSpent: 1200000,
  percentage: 120.0,
  remaining: -200000,
  cycleOn: 1,
);

final warningItem = BudgetSummaryItem(
  id: 3,
  categoryId: 3,
  categoryName: 'Belanja Harian',
  categoryNameEn: 'Daily Shopping',
  categoryIcon: '🛍️',
  budgetAmount: 2000000,
  actualSpent: 1600000,
  percentage: 80.0,
  remaining: 400000,
  cycleOn: 1,
);

void main() {
  setUp(() => initTestSecureStorage());

  group('BudgetsScreen', () {
    testWidgets('shows shimmer loading when loading', (tester) async {
      await tester.pumpWidget(buildBudgetsApp(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsNothing);
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

      // Scroll down to see all items (summary card pushes 3rd item off-screen)
      await tester.dragUntilVisible(
        find.text('Daily Shopping'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      expect(find.text('Food & Drinks'), findsOneWidget);
      expect(find.text('Transport & Fuel'), findsOneWidget);
      expect(find.text('Daily Shopping'), findsOneWidget);
    });

    testWidgets('shows FABs for suggestions and add budget', (tester) async {
      await tester.pumpWidget(buildBudgetsApp());
      expect(find.byIcon(Icons.add), findsOneWidget);
      // auto_awesome appears in both FAB and empty state button
      expect(find.byIcon(Icons.auto_awesome), findsAtLeast(1));
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
