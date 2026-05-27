import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/widgets/loading_indicator.dart';
import 'package:wealthtrack/shared/widgets/error_display.dart';
import 'package:wealthtrack/shared/widgets/empty_state.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';

Widget wrap(Widget w) => MaterialApp(theme: AppTheme.light, home: w);

void main() {
  group('LoadingIndicator', () {
    testWidgets('shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ErrorDisplay', () {
    testWidgets('shows message and retry button when onRetry provided', (tester) async {
      var retried = false;
      await tester.pumpWidget(wrap(ErrorDisplay(
        message: 'Network error occurred',
        onRetry: () => retried = true,
      )));
      expect(find.text('Network error occurred'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('shows message without retry button', (tester) async {
      await tester.pumpWidget(wrap(const ErrorDisplay(message: 'Something broke')));
      expect(find.text('Something broke'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows error icon', (tester) async {
      await tester.pumpWidget(wrap(const ErrorDisplay(message: 'Error')));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows message', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: 'No data available')));
      expect(find.text('No data available'), findsOneWidget);
    });

    testWidgets('shows inbox icon', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: 'Empty')));
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });
  });
}
