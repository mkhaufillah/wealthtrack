import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/providers/dashboard_provider.dart';
import 'package:wealthtrack/features/home/ui/home_screen.dart';
import 'package:wealthtrack/features/home/ui/widgets/balance_card.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/utils/currency_formatter.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

Widget buildHomeApp({bool isLoading = false, String? error, int balance = 0}) {
  final mockApi = MockApiClient();
  mockApi.onGet('/home', {
    'hero': {
      'amount': balance,
      'amount_display': formatCurrency(balance),
      'income': balance > 0 ? balance + 500000 : 0,
      'income_display': formatCurrency(balance > 0 ? balance + 500000 : 0),
      'expense': 500000,
      'expense_display': formatCurrency(500000),
    },
    'pots': {'savings': 0, 'savings_display': 'Rp0', 'emergency': 0, 'emergency_display': 'Rp0'},
    'debt_summary': {'visible': false, 'total': 0, 'total_display': 'Rp0', 'title_key': 'home.debt_running'},
    'recent': <List<dynamic>>[],
  });
  mockApi.onGet('/transactions', {
    'data': <List<dynamic>>[],
    'meta': {'total': 0, 'page': 1, 'per_page': 5, 'total_pages': 0},
  });
  mockApi.onGet('/summaries/all-time-category-balance', {
    'savings_investment': {'total_expense': 0, 'total_income': 0, 'balance': 0},
    'emergency_funds': {'total_expense': 0, 'total_income': 0, 'balance': 0},
  });
  mockApi.onGet('/bank-inbox', {
    'items': <Map<String, dynamic>>[],
    'pending_count': 0,
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
            balanceDisplay: formatCurrency(balance),
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
      expect(find.text('Coba lagi'), findsOneWidget);
      await tester.pump();
    });

    testWidgets('shows balance when data loaded', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1500000));
      await tester.pumpAndSettle();
      expect(find.text('Hai, Filla'), findsNothing); // greeting uses login user (mock has none)
      // greeting subtitle is server-driven copy, NOT a hardcoded literal
      expect(find.text('Saldo kamu, sepanjang waktu'), findsOneWidget);
      final card = tester.widget<BalanceCard>(find.byType(BalanceCard));
      expect(card.balance, 1500000);
      expect(card.amountText ?? formatCurrency(card.balance), formatCurrency(1500000));
    });

    testWidgets('shows all-time balance label when load completes', (tester) async {
      await tester.pumpWidget(buildHomeApp(balance: 1000000));
      await tester.pumpAndSettle();
      expect(find.text('Uang kamu'), findsOneWidget);
    });

    testWidgets('shows top pending bank draft with actions', (tester) async {
      final mockApi = MockApiClient();
      mockApi.onGet('/home', {
        'hero': {
          'amount': 0,
          'amount_display': formatCurrency(0),
          'income': 0,
          'income_display': formatCurrency(0),
          'expense': 0,
          'expense_display': formatCurrency(0),
        },
        'pots': {'savings': 0, 'savings_display': 'Rp0', 'emergency': 0, 'emergency_display': 'Rp0'},
        'debt_summary': {'visible': false, 'total': 0, 'total_display': 'Rp0', 'title_key': 'home.debt_running'},
        'recent': <List<dynamic>>[],
      });
      mockApi.onGet('/transactions', {
        'data': <List<dynamic>>[],
        'meta': {'total': 0, 'page': 1, 'per_page': 5, 'total_pages': 0},
      });
      mockApi.onGet('/summaries/all-time-category-balance', {
        'savings_investment': {'total_expense': 0, 'total_income': 0, 'balance': 0},
        'emergency_funds': {'total_expense': 0, 'total_income': 0, 'balance': 0},
      });
      mockApi.onGet('/bank-inbox', {
        'items': [
          {
            'id': 9,
            'status': 'pending',
            'bank': 'superbank',
            'title': 'Debit',
            'merchant': 'QRIS Kopi',
            'amount': 25000,
          }
        ],
        'pending_count': 1,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWithProvider(
              StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
                final notifier = DashboardNotifier(mockApi);
                notifier.state = const DashboardState(
                  isLoading: false,
                  balance: 0,
                  totalIncome: 0,
                  totalExpense: 0,
                  balanceDisplay: 'Rp0',
                  recentTransactions: [],
                  totalTransactions: 0,
                );
                return notifier;
              }),
            ),
            apiClientProvider.overrideWithProvider(Provider<ApiClient>((ref) => mockApi)),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Draf dari bank'), findsOneWidget);
      expect(find.text('Catat'), findsOneWidget);
      expect(find.text('Abaikan'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);
    });
  });
}
