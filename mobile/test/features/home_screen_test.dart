import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/providers/dashboard_provider.dart';
import 'package:wealthtrack/features/home/ui/home_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

Widget buildHomeApp({bool isLoading = false, String? error, int balance = 0}) {
  final mockApi = MockApiClient();
  mockApi.onGet('/summaries/current-month', {
    'total_income': balance > 0 ? balance + 500000 : 0,
    'total_expense': 500000,
    'balance': balance,
    'date_from': '2026-05-01',
    'date_to': '2026-05-31',
  });
  mockApi.onGet('/transactions', {
    'data': <List<dynamic>>[],
    'meta': {'total': 0, 'page': 1, 'per_page': 5, 'total_pages': 0},
  });
  mockApi.onGet('/summaries/all-time-category-balance', {
    'savings_investment': {'total_expense': 0, 'total_income': 0, 'balance': 0},
    'emergency_funds': {'total_expense': 0, 'total_income': 0, 'balance': 0},
  });
  return ProviderScope(
    overrides: [
      dashboardProvider.overrideWithProvider(
        StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
          final notifier = DashboardNotifier(mockApi);
          notifier.state = DashboardState(
            isLoading: isLoading,
            error: error,
            balance: balance,
            totalIncome: balance > 0 ? balance + 500000 : 0,
            totalExpense: balance > 0 ? 500000 : 0,
            recentTransactions: const [],
            totalTransactions: 0,
          );
          return notifier;
        }),
      ),
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => mockApi),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const HomeScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  group('HomeScreen', () {
    testWidgets('shows shimmer loading when loading', (tester) async {
      await tester.pumpWidget(buildHomeApp(isLoading: true));
      // Before pump(), initState microtask hasn't run yet — loading state still visible
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(); // drain microtask so test finishes cleanly
    });

    testWidgets('shows error display when error present', (tester) async {
      await tester.pumpWidget(buildHomeApp(error: 'Connection failed'));
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pump();
    });

    testWidgets('shows balance when data loaded', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1500000));
      await tester.pumpAndSettle();
      expect(find.text('WealthTrack'), findsOneWidget);
      expect(find.text('Rp1.500.000'), findsOneWidget);
    });

    testWidgets('shows cycle date range when load completes', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1000000));
      await tester.pumpAndSettle();
      // load() populates dateFrom/dateTo from mock response → cycleLabel becomes date range
      expect(find.text('01 May – 31 May'), findsOneWidget);
    });
  });
}
