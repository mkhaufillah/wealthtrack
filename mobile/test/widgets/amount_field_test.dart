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
      expect(find.text('Rp ', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows hint text 0 when empty and unfocused', (tester) async {
      await tester.pumpWidget(buildAmountField());
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('hides hint 0 when field gains focus', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('0'), findsNothing);
      expect(find.text('Rp ', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows raw digits when focused', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '50000');
      await tester.pump();
      expect(find.text('0'), findsNothing);
      // Should show raw digits when focused
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '50000');
    });

    testWidgets('formats amount with thousand separators on unfocus',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(), // focusable sibling
              AmountField(controller: controller),
            ],
          ),
        ),
      ));

      // Focus the amount field
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '50000');
      await tester.pump();

      // Move focus to sibling
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      // Should be formatted on unfocus
      expect(controller.text, '50.000');
    });

    testWidgets('unformats amount on focus gain', (tester) async {
      final controller = TextEditingController(text: '50.000');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(),
              AmountField(controller: controller),
            ],
          ),
        ),
      ));
      await tester.pump();

      // Initially formatted on unfocus
      expect(controller.text, '50.000');

      // Focus the amount field
      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      // Should show raw digits
      expect(controller.text, '50000');
    });

    testWidgets('shows hint 0 again when unfocused and empty',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(),
              AmountField(controller: controller),
            ],
          ),
        ),
      ));

      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(find.text('0'), findsNothing);

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('accepts numeric input', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '25000');
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '25000');
    });

    testWidgets('formats initial value', (tester) async {
      await tester.pumpWidget(buildAmountField(initialText: '150000'));
      await tester.pump();
      // Should format immediately
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '150.000');
      // Hint should not show
      expect(find.text('0'), findsNothing);
    });
  });
}
