import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/budgets/providers/budget_suggestion_provider.dart';
import 'package:wealthtrack/features/budgets/models/budget_model.dart';
import 'package:wealthtrack/features/budgets/data/budget_repository.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

void main() {
  late BudgetSuggestionNotifier notifier;

  final sampleItems = [
    BudgetSuggestion(
      categoryId: 1,
      categoryName: 'Makanan & Minuman',
      categoryNameEn: 'Food & Drinks',
      categoryIcon: '🍔',
      suggestedAmount: 1500000,
      historicalAvg: 1420000,
      historicalMax: 1850000,
      monthsAnalyzed: 3,
    ),
    BudgetSuggestion(
      categoryId: 2,
      categoryName: 'Transportasi & Bensin',
      categoryNameEn: 'Transport & Fuel',
      categoryIcon: '🚗',
      suggestedAmount: 500000,
      historicalAvg: 450000,
      historicalMax: 600000,
      monthsAnalyzed: 3,
    ),
  ];

  final sampleResponse = BudgetSuggestionResponse(sampleItems, 2000000, 8000000, '');

  final sampleWithExisting = BudgetSuggestionResponse(
    [
      BudgetSuggestion(
        categoryId: 1,
        categoryName: 'Makanan & Minuman',
        categoryNameEn: 'Food & Drinks',
        categoryIcon: '🍔',
        suggestedAmount: 1500000,
        historicalAvg: 1420000,
        historicalMax: 1850000,
        monthsAnalyzed: 3,
        hasBudget: true,
        existingAmount: 1200000,
      ),
      BudgetSuggestion(
        categoryId: 2,
        categoryName: 'Transportasi & Bensin',
        categoryNameEn: 'Transport & Fuel',
        categoryIcon: '🚗',
        suggestedAmount: 500000,
        historicalAvg: 450000,
        historicalMax: 600000,
        monthsAnalyzed: 3,
      ),
    ],
    500000,
    8000000,
    '',
  );

  setUp(() {
    initTestSecureStorage();
    notifier = BudgetSuggestionNotifier(MockBudgetRepo(), MockApiClient());
  });

  group('initial state', () {
    test('starts with default values', () {
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, null);
      expect(notifier.state.response, null);
      expect(notifier.state.numAccepted, 0);
      expect(notifier.state.isApplying, false);
    });
  });

  group('load', () {
    test('sets loading while fetching', () async {
      final future = notifier.load('2026-05');
      expect(notifier.state.isLoading, true);
      expect(notifier.state.error, null);
      await future;
    });

    test('sets response on success', () async {
      await notifier.load('2026-05');
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, null);
    });

    test('sets error on failure', () async {
      final failingNotifier = BudgetSuggestionNotifier(FailingMockBudgetRepo(), MockApiClient());
      await failingNotifier.load('2026-05');
      expect(failingNotifier.state.isLoading, false);
      expect(failingNotifier.state.error, isNotNull);
    });
  });

  group('toggleAccept', () {
    test('does nothing when response is null', () {
      notifier.toggleAccept(1);
      expect(notifier.state.numAccepted, 0);
    });

    test('toggles a category from unaccepted to accepted', () {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      expect(notifier.state.numAccepted, 0);

      notifier.toggleAccept(1);
      expect(notifier.state.numAccepted, 1);

      final item =
          notifier.state.response!.items.firstWhere((i) => i.categoryId == 1);
      expect(item.accepted, true);
    });

    test('toggles back from accepted to unaccepted', () {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      notifier.toggleAccept(1);
      expect(notifier.state.numAccepted, 1);

      notifier.toggleAccept(1);
      expect(notifier.state.numAccepted, 0);

      final item =
          notifier.state.response!.items.firstWhere((i) => i.categoryId == 1);
      expect(item.accepted, false);
    });
  });

  group('toggleSelectAll', () {
    test('selects all non-existing budget items', () {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      notifier.toggleSelectAll(true);
      expect(notifier.state.numAccepted, 2);
    });

    test('clears all selections', () {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      notifier.toggleSelectAll(true);
      expect(notifier.state.numAccepted, 2);

      notifier.toggleSelectAll(false);
      expect(notifier.state.numAccepted, 0);
    });

    test('does not toggle items with existing budgets', () {
      notifier.state = notifier.state.copyWith(response: sampleWithExisting);
      notifier.toggleSelectAll(true);
      // Only category 2 (no existing budget) should be selected
      expect(notifier.state.numAccepted, 1);

      final item1 =
          notifier.state.response!.items.firstWhere((i) => i.categoryId == 1);
      expect(item1.accepted, false); // existing budget, should NOT be toggled
    });
  });

  group('applySelected', () {
    test('returns false when response is null', () async {
      final result = await notifier.applySelected('2026-05');
      expect(result, false);
    });

    test('returns true when nothing selected (empty apply is no-op)', () async {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      final result = await notifier.applySelected('2026-05');
      expect(result, true);
    });

    test('returns true when selected items applied', () async {
      notifier.state = notifier.state.copyWith(response: sampleResponse);
      notifier.toggleAccept(1);
      final result = await notifier.applySelected('2026-05');
      expect(result, true);
      expect(notifier.state.isApplying, false);
    });
  });
}

/// Mock BudgetRepository using concrete implementation pattern (same as existing test mocks).
class MockBudgetRepo extends BudgetRepository {
  MockBudgetRepo() : super(MockApiClient());

  @override
  Future<BudgetSuggestionResponse> getSuggestions(
      String month, {int numCycles = 3}) async {
    return BudgetSuggestionResponse([], 0, 0, '');
  }

  @override
  Future<BudgetModel> create(Map<String, dynamic> data) async {
    return BudgetModel(
      id: 1,
      month: data['month'] as String? ?? '2026-05',
      categoryId: data['category_id'] as int? ?? 0,
      amount: data['amount'] as int? ?? 0,
      categoryName: '',
      categoryNameEn: '',
      categoryIcon: '📦',
    );
  }
}

/// Mock BudgetRepository that always fails.
class FailingMockBudgetRepo extends BudgetRepository {
  FailingMockBudgetRepo() : super(MockApiClient());

  @override
  Future<BudgetSuggestionResponse> getSuggestions(
      String month, {int numCycles = 3}) async {
    throw Exception('API error');
  }

  @override
  Future<BudgetModel> create(Map<String, dynamic> data) async {
    throw Exception('API error');
  }
}
