import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/ui/widgets/amount_field.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

Widget buildAmountField({String initialText = ''}) {
  final controller = TextEditingController(text: initialText);
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: AmountField(controller: controller),
    ),
  );
}

void main() {
  group('AmountField', () {
    testWidgets('shows Rp prefix', (tester) async {
      await tester.pumpWidget(buildAmountField());
      // prefixText='Rp ' renders as a separate Text widget
      expect(find.text('Rp ', skipOffstage: false), findsOneWidget);
      // hintText='0' renders separately when empty and unfocused
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('shows hint text 0 when empty and unfocused', (tester) async {
      await tester.pumpWidget(buildAmountField());
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('hides hint 0 when field gains focus', (tester) async {
      await tester.pumpWidget(buildAmountField());
      // Tap the text field to give it focus
      await tester.tap(find.byType(TextField));
      await tester.pump();
      // '0' hint should disappear, only 'Rp ' prefix remains
      expect(find.text('0'), findsNothing);
      expect(find.text('Rp ', skipOffstage: false), findsOneWidget);
    });

    testWidgets('hides hint 0 when text is entered', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '50000');
      await tester.pump();
      // '0' hint should not appear since there's text
      expect(find.text('0'), findsNothing);
      // The typed value should be shown (with prefix still visible)
      expect(find.text('Rp ', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows hint 0 again when unfocused and empty', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              // Focusable sibling so we can reliably move focus away
              const TextField(),
              AmountField(controller: controller),
            ],
          ),
        ),
      ));

      // Focus the amount field (second TextField in the Column)
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(find.text('0'), findsNothing);

      // Move focus to the sibling field above
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      // Since still empty, hint should reappear
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('accepts numeric input', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '25000');
      await tester.pump();
      // The controller should have the text
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '25000');
    });

    testWidgets('supports custom initial value', (tester) async {
      await tester.pumpWidget(buildAmountField(initialText: '150000'));
      await tester.pump();
      // With initial text, hint should not show (hasText = true)
      expect(find.text('Rp 0'), findsNothing);
    });
  });
}
