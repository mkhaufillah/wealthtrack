import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/reports/ui/reports_screen.dart';
import 'package:wealthtrack/features/reports/providers/report_provider.dart';
import 'package:wealthtrack/features/reports/data/report_repository.dart';
import 'package:wealthtrack/features/reports/models/report_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

/// Helper to configure a MockApiClient with canned report data.
MockApiClient setupReportMockApi({
  required String month,
  int totalIncome = 5000000,
  int totalExpense = 3000000,
  int balance = 2000000,
  List<Map<String, dynamic>> categories = const [],
  List<Map<String, dynamic>> dailySnapshot = const [],
}) {
  final api = MockApiClient();
  api.onGet('/summaries/monthly', {
    'month': month,
    'total_income': totalIncome,
    'total_expense': totalExpense,
    'balance': balance,
    'categories': categories,
    'daily_snapshot': dailySnapshot,
  });
  // Household report (empty by default so no household sections shown)
  api.onGet('/summaries/household', {
    'date_from': '',
    'date_to': '',
    'total_income': 0,
    'total_expense': 0,
    'balance': 0,
    'by_category': [],
    'by_user': [],
  });
  // Household transactions (empty)
  api.onGet('/transactions/household', {'data': []});
  return api;
}

Widget buildReportsApp({
  bool isLoading = false,
  String? error,
  MonthlyReport? monthly,
  HouseholdReport? household,
  List<MonthlyTrend> trend = const [],
  MockApiClient? apiClient,
}) {
  final mockApi = apiClient ?? MockApiClient();

  return ProviderScope(
    overrides: [
      reportProvider.overrideWithProvider(
        StateNotifierProvider<ReportNotifier, ReportState>((ref) {
          final notifier = ReportNotifier(
            ReportRepository(mockApi),
            mockApi,
          );
          notifier.state = ReportState(
            isLoading: isLoading,
            error: error,
            monthly: monthly,
            household: household,
            trend: trend,
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
      home: const ReportsScreen(),
    ),
  );
}

final sampleCategory = CategoryBreakdown(
  categoryId: 1,
  categoryName: 'Makanan & Minuman',
  icon: '🍔',
  total: 1500000,
  count: 10,
  percentage: 50.0,
);

final sampleCategory2 = CategoryBreakdown(
  categoryId: 2,
  categoryName: 'Transportasi & Bensin',
  icon: '🚗',
  total: 800000,
  count: 5,
  percentage: 26.7,
);

final sampleMonthlyReport = MonthlyReport(
  month: '2026-05',
  totalIncome: 5000000,
  totalExpense: 3000000,
  balance: 2000000,
  categories: [sampleCategory, sampleCategory2],
  dailySnapshot: [
    DailySnapshot(date: '2026-05-01', expense: 150000, income: 0),
    DailySnapshot(date: '2026-05-02', expense: 50000, income: 500000),
  ],
);

final sampleHouseholdReport = HouseholdReport(
  dateFrom: '2026-05-01',
  dateTo: '2026-05-31',
  totalIncome: 8000000,
  totalExpense: 5000000,
  balance: 3000000,
  byCategory: [
    CategoryBreakdown(
      categoryId: 1,
      categoryName: 'Makanan & Minuman',
      icon: '🍔',
      total: 2000000,
      count: 8,
      percentage: 40.0,
    ),
  ],
  byUser: [
    UserBreakdown(
      userId: 1,
      displayName: 'Filla',
      totalExpense: 2000000,
      totalIncome: 3000000,
    ),
    UserBreakdown(
      userId: 2,
      displayName: 'Nahda',
      totalExpense: 3000000,
      totalIncome: 5000000,
    ),
  ],
);

final sampleTrend = [
  MonthlyTrend(
      month: '2026-01',
      totalIncome: 4000000,
      totalExpense: 3500000,
      balance: 500000),
  MonthlyTrend(
      month: '2026-02',
      totalIncome: 4500000,
      totalExpense: 3200000,
      balance: 1300000),
];

void main() {
  setUp(() => initTestSecureStorage());

  group('ReportsScreen', () {
    testWidgets('shows Reports title in app bar', (tester) async {
      await tester.pumpWidget(buildReportsApp());
      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets('shows loading indicator when loading', (tester) async {
      await tester.pumpWidget(buildReportsApp(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error display when error present', (tester) async {
      await tester.pumpWidget(
          buildReportsApp(error: 'Failed to load reports'));
      expect(find.text('Failed to load reports'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error display with retry button', (tester) async {
      await tester.pumpWidget(
        buildReportsApp(error: 'Something went wrong'),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows month picker with navigation arrows', (tester) async {
      await tester.pumpWidget(buildReportsApp());
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows RefreshIndicator', (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
        dailySnapshot: [
          {'date': '2026-05-01', 'expense': 150000, 'income': 0},
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump(); // Let post-frame callback resolve
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows summary stat cards when data loaded', (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump(); // Let post-frame callback resolve
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
    });

    testWidgets('shows category breakdown section', (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump();
      expect(find.text('Category Breakdown'), findsOneWidget);
      expect(find.text('Category Comparison'), findsOneWidget);
    });

    testWidgets('shows translated category names in breakdown',
        (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump();
      expect(find.text('Food & Drinks'), findsOneWidget);
    });

    testWidgets('shows daily breakdown section', (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
        dailySnapshot: [
          {'date': '2026-05-01', 'expense': 150000, 'income': 0},
          {'date': '2026-05-02', 'expense': 50000, 'income': 500000},
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump();
      expect(find.text('Daily Breakdown'), findsOneWidget);
    });

    testWidgets('shows household split when household data provided',
        (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(buildReportsApp(
        apiClient: mockApi,
        monthly: sampleMonthlyReport,
        household: sampleHouseholdReport,
      ));
      await tester.pump();
      expect(find.text('Household Split'), findsOneWidget);
      expect(find.text('Filla'), findsOneWidget);
      expect(find.text('Nahda'), findsOneWidget);
    });

    testWidgets('shows monthly trend when trend data provided',
        (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(buildReportsApp(
        apiClient: mockApi,
        monthly: sampleMonthlyReport,
        trend: sampleTrend,
      ));
      await tester.pump();
      expect(find.text('Monthly Trend'), findsOneWidget);
    });

    testWidgets('shows export button at bottom', (tester) async {
      final mockApi = setupReportMockApi(
        month: '2026-05',
        categories: [
          {
            'category_id': 1,
            'category_name': 'Makanan & Minuman',
            'icon': '🍔',
            'total': 1500000,
            'count': 10,
            'percentage': 50.0
          },
        ],
      );
      await tester.pumpWidget(
          buildReportsApp(apiClient: mockApi, monthly: sampleMonthlyReport));
      await tester.pump();
      // Scroll to bottom for export button
      await tester.dragUntilVisible(
        find.text('Export Report'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      expect(find.text('Export Report'), findsOneWidget);
    });
  });
}
