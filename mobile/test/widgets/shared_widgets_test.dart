import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/widgets/loading_indicator.dart';
import 'package:wealthtrack/shared/widgets/error_display.dart';
import 'package:wealthtrack/shared/widgets/empty_state.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/core/ui/app_icons.dart';
import 'package:wealthtrack/core/ui/brand_mark.dart';
import 'package:hugeicons/hugeicons.dart';

Widget wrap(Widget w) => MaterialApp(theme: AppTheme.light, home: w);

void main() {
  group('LoadingIndicator', () {
    testWidgets('shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ErrorDisplay', () {
    testWidgets('shows mascot, title, message and refresh', (tester) async {
      var retried = false;
      await tester.pumpWidget(wrap(ErrorDisplay(
        message: 'Network error occurred',
        onRetry: () => retried = true,
      )));
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Waduh, ada yang gak beres'), findsOneWidget);
      expect(find.text('Network error occurred'), findsOneWidget);
      expect(find.text('Muat ulang'), findsOneWidget);
      await tester.tap(find.text('Muat ulang'));
      expect(retried, isTrue);
    });

    testWidgets('hides raw html', (tester) async {
      await tester.pumpWidget(wrap(const ErrorDisplay(
        message: '<html><body>502 Bad Gateway</body></html>',
      )));
      expect(find.textContaining('<html'), findsNothing);
      expect(find.text('Ada yang gak beres. Coba lagi ya.'), findsOneWidget);
      expect(find.text('Muat ulang'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows message', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: 'No data available')));
      expect(find.text('No data available'), findsOneWidget);
    });

    testWidgets('shows inbox icon', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: 'Empty')));
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedInbox), findsOneWidget);
    });
  });
}
