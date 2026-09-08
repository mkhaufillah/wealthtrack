import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/profile/ui/config_admin_screen.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

Widget buildConfigAdmin(MockApiClient api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => api),
      ),
    ],
    child: MaterialApp(
      home: ConfigAdminScreen(),
    ),
  );
}

void main() {
  testWidgets('loads format + flags from /ui/config', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/config', {
      'items': [
        {'key': 'format', 'value': {'currency': 'IDR', 'currency_prefix': 'Rp', 'group_sep': '.', 'decimal_sep': ','}},
        {'key': 'flags', 'value': {'home_all_time': true}},
      ],
    });
    await tester.pumpWidget(buildConfigAdmin(api));
    await tester.pumpAndSettle();

    expect(api.lastGetPath, '/ui/config');
    expect(find.text('Format uang'), findsOneWidget);
    expect(find.text('Fitur flags'), findsOneWidget);
    // prefix field pre-filled (first TextField with text Rp; hint also shows Rp)
    expect(find.widgetWithText(TextField, 'Rp').first, findsOneWidget);
  });

  testWidgets('saving format calls PUT with edited prefix', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/config', {
      'items': [
        {'key': 'format', 'value': {'currency': 'IDR', 'currency_prefix': 'Rp', 'group_sep': '.', 'decimal_sep': ','}},
        {'key': 'flags', 'value': {'home_all_time': true}},
      ],
    });
    api.onPut('/ui/config/format', {'key': 'format', 'value': {}});
    await tester.pumpWidget(buildConfigAdmin(api));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Rp.');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan').first);
    await tester.pumpAndSettle();

    expect(api.lastPutPath, '/ui/config/format');
    final value = (api.lastPutData as Map)['value'] as Map;
    expect(value['currency_prefix'], 'Rp.');
  });

  testWidgets('saving flags calls PUT /ui/config/flags', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/config', {
      'items': [
        {'key': 'format', 'value': {'currency': 'IDR', 'currency_prefix': 'Rp', 'group_sep': '.', 'decimal_sep': ','}},
        {'key': 'flags', 'value': {'home_all_time': true}},
      ],
    });
    api.onPut('/ui/config/flags', {'key': 'flags', 'value': {}});
    await tester.pumpWidget(buildConfigAdmin(api));
    await tester.pumpAndSettle();

    // second FilledButton = "Simpan" under the flags card
    final saveButtons = find.byType(FilledButton);
    expect(saveButtons, findsNWidgets(3));
    await tester.ensureVisible(saveButtons.at(1));
    await tester.pumpAndSettle();
    await tester.tap(saveButtons.at(1));
    await tester.pumpAndSettle();

    expect(api.lastPutPath, '/ui/config/flags');
    final value = (api.lastPutData as Map)['value'] as Map;
    expect(value['home_all_time'], isTrue);
  });

  testWidgets('shows error state when load fails', (tester) async {
    final api = MockApiClient();
    await tester.pumpWidget(buildConfigAdmin(api));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('theme swatch row renders and saving preset PUTs both keys',
      (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/config', {
      'items': [
        {'key': 'format', 'value': {'currency': 'IDR', 'currency_prefix': 'Rp', 'group_sep': '.', 'decimal_sep': ','}},
        {'key': 'flags', 'value': {'home_all_time': true}},
        {'key': 'theme.light', 'value': {'accent': '#F3A6B8'}},
        {'key': 'theme.dark', 'value': {'accent': '#E9A0B2'}},
      ],
    });
    api.onPut('/ui/config/theme.light', {'key': 'theme.light', 'value': {}});
    api.onPut('/ui/config/theme.dark', {'key': 'theme.dark', 'value': {}});
    await tester.pumpWidget(buildConfigAdmin(api));
    await tester.pumpAndSettle();

    // theme card is below the fold — scroll to it first
    await tester.scrollUntilVisible(find.text('Warna tema'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Warna tema'), findsOneWidget);
    for (final name in ['peach', 'ocean', 'forest', 'rose']) {
      expect(find.text(name), findsOneWidget);
    }

    // pick ocean, save (third FilledButton = theme save)
    await tester.tap(find.text('ocean'));
    await tester.pumpAndSettle();
    final buttons = find.byType(FilledButton);
    await tester.ensureVisible(buttons.at(2));
    await tester.pumpAndSettle();
    await tester.tap(buttons.at(2));
    await tester.pumpAndSettle();

    expect(api.lastPutPath, '/ui/config/theme.dark');
    expect((api.lastPutData as Map)['preset'], 'ocean');
  });
}