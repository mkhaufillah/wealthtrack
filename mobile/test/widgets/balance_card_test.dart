import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/home/ui/widgets/balance_card.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

Widget wrap(Widget w) => MaterialApp(theme: AppTheme.light, home: w);

void main() {
  group('BalanceCard', () {
    testWidgets('does not use money emoji', (tester) async {
      await tester.pumpWidget(wrap(
        const BalanceCard(balance: 1000000, income: 3000000, expense: 2000000),
      ));
      expect(find.text('💰'), findsNothing);
    });

    testWidgets('displays Uang kamu header', (tester) async {
      await tester.pumpWidget(wrap(
        const BalanceCard(balance: 0, income: 0, expense: 0),
      ));
      expect(find.text('Uang kamu'), findsOneWidget);
    });

    testWidgets('formats balance correctly', (tester) async {
      await tester.pumpWidget(wrap(
        const BalanceCard(balance: 1500000, income: 5000000, expense: 3500000),
      ));
      expect(find.text('Rp1.500.000'), findsOneWidget);
    });

    testWidgets('shows Masuk and Keluar labels', (tester) async {
      await tester.pumpWidget(wrap(
        const BalanceCard(balance: 500000, income: 1000000, expense: 500000),
      ));
      expect(find.text('Masuk'), findsOneWidget);
      expect(find.text('Keluar'), findsOneWidget);
    });

    testWidgets('displays zero balance', (tester) async {
      await tester.pumpWidget(wrap(
        const BalanceCard(balance: 0, income: 0, expense: 0),
      ));
      expect(find.text('Rp0'), findsAtLeast(1));
    });
  });
}
