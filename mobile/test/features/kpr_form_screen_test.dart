import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/features/debt/kpr/ui/kpr_form_screen.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

Widget buildKprApp(MockApiClient api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => api),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const KPRFormScreen(),
    ),
  );
}

void main() {
  testWidgets('calculate posts to server-driven /kpr/calculate', (tester) async {
    final api = MockApiClient();
    // household check fired in initState
    api.onGet('/households/me', {
      'id': 1,
      'name': 'Keluarga',
      'member_count': 2,
    });
    api.onPost('/kpr/calculate', {
      'monthly_payment': 5000000,
      'total_payment': 900000000,
      'total_interest': 100000000,
    });

    await tester.pumpWidget(buildKprApp(api));
    await tester.pumpAndSettle();

    // property price + down payment fields share hint 'Rp 0' — first two
    Finder amountField(int i) => find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == 'Rp 0').at(i);

    await tester.enterText(amountField(0), '500000000');
    await tester.enterText(amountField(1), '100000000');
    await tester.pumpAndSettle();

    // Hitung button sits below the fold in a lazy ListView — scroll first
    await tester.scrollUntilVisible(find.text('Hitung'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hitung'));
    await tester.pumpAndSettle();

    expect(api.lastPostPath, '/kpr/calculate');
    final data = api.lastPostData as Map<String, dynamic>;
    expect(data['property_price'], 500000000);
    expect(data['down_payment'], 100000000);
    expect(data['interest_type'], 'fixed');
    // result dialog surfaced with server-computed monthly payment
    expect(find.textContaining('5.000.000'), findsOneWidget);
  });

  testWidgets('fill missing amount shows hint instead of posting', (tester) async {
    final api = MockApiClient();
    api.onGet('/households/me', {
      'id': 1,
      'name': 'Keluarga',
      'member_count': 2,
    });

    await tester.pumpWidget(buildKprApp(api));
    await tester.pumpAndSettle();

    // Hitung button below the fold in a lazy ListView — scroll first
    await tester.scrollUntilVisible(find.text('Hitung'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hitung'));
    await tester.pumpAndSettle();

    expect(api.lastPostPath, isNull); // did not hit server
  });
}