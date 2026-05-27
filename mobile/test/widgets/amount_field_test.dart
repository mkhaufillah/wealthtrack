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
    testWidgets('shows Rp 0 hint when empty and unfocused', (tester) async {
      await tester.pumpWidget(buildAmountField());
      expect(find.text('Rp 0'), findsOneWidget);
    });

    testWidgets('hides hint when field gains focus', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Rp 0'), findsNothing);
    });

    testWidgets('shows raw digits when focused', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '50000');
      await tester.pump();
      // Controller stores raw digits only when focused
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '50000');
    });

    testWidgets('formats amount on unfocus', (tester) async {
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
      await tester.enterText(find.byType(TextField).last, '50000');
      await tester.pump();

      // Move focus to sibling
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      expect(controller.text, 'Rp 50.000');
    });

    testWidgets('unformats amount on focus gain', (tester) async {
      final controller = TextEditingController(text: 'Rp 50.000');
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

      expect(controller.text, 'Rp 50.000');

      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      // Raw digits only when focused — no "Rp" prefix
      expect(controller.text, '50000');
    });

    testWidgets('shows hint again when unfocused and empty', (tester) async {
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
      expect(find.text('Rp 0'), findsNothing);

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(find.text('Rp 0'), findsOneWidget);
    });

    testWidgets('accepts numeric input', (tester) async {
      await tester.pumpWidget(buildAmountField());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '25000');
      await tester.pump();
      // Raw digits when focused
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '25000');
    });

    testWidgets('formats initial value', (tester) async {
      await tester.pumpWidget(buildAmountField(initialText: '150000'));
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      // Initially unfocused → formatted with "Rp" prefix
      expect(textField.controller?.text, 'Rp 150.000');
      expect(find.text('0'), findsNothing);
    });
  });
}
