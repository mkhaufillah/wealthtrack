import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/providers/dashboard_provider.dart';
import 'package:wealthtrack/features/home/ui/home_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import '../helpers/mocks.dart';

Widget buildHomeApp({bool isLoading = false, String? error, int balance = 0}) {
  return ProviderScope(
    overrides: [
      dashboardProvider.overrideWithProvider(
        StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
          final notifier = DashboardNotifier(MockApiClient());
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
    testWidgets('shows loading indicator when loading', (tester) async {
      await tester.pumpWidget(buildHomeApp(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error display when error present', (tester) async {
      await tester.pumpWidget(buildHomeApp(error: 'Connection failed'));
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows balance when data loaded', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1500000));
      expect(find.text('WealthTrack'), findsOneWidget);
      expect(find.text('Rp1.500.000'), findsOneWidget);
    });

    testWidgets('shows Monthly Balance header', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1000000));
      expect(find.text('Monthly Balance'), findsOneWidget);
    });
  });
}
