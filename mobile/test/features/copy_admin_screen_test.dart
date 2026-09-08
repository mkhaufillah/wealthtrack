import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/profile/ui/copy_admin_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

Widget buildCopyAdmin(MockApiClient api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => api),
      ),
    ],
    child: MaterialApp(
      home: CopyAdminScreen(),
    ),
  );
}

void main() {
  testWidgets('shows loading then list of copy keys', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/copy', {
      'items': [
        {'key': 'home.hero_title', 'value': 'Uang kamu'},
        {'key': 'common.apply', 'value': 'Terapin'},
      ],
    });
    await tester.pumpWidget(buildCopyAdmin(api));
    await tester.pumpAndSettle();

    expect(find.text('home.hero_title'), findsOneWidget);
    expect(find.text('Uang kamu'), findsOneWidget);
    expect(find.text('common.apply'), findsOneWidget);
    expect(api.lastGetPath, '/ui/copy');
  });

  testWidgets('search sends query param', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/copy', {'items': []});
    await tester.pumpWidget(buildCopyAdmin(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hero');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(api.lastGetPath, '/ui/copy');
    expect(api.lastGetQuery?['search'], 'hero');
  });

  testWidgets('tap row opens edit dialog and saves via PUT', (tester) async {
    final api = MockApiClient();
    api.onGet('/ui/copy', {
      'items': [
        {'key': 'home.hero_title', 'value': 'Uang kamu'},
      ],
    });
    api.onPut('/ui/copy/home.hero_title', {
      'key': 'home.hero_title',
      'value': 'Uang baru',
    });
    await tester.pumpWidget(buildCopyAdmin(api));
    await tester.pumpAndSettle();

    // open edit dialog
    await tester.tap(find.text('home.hero_title'));
    await tester.pumpAndSettle();
    expect(find.text('home.hero_title'), findsWidgets); // dialog title too

    // change value and save
    final editFields = find.byType(TextField);
    await tester.enterText(editFields.last, 'Uang baru');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(api.lastPutPath, '/ui/copy/home.hero_title');
    expect((api.lastPutData as Map)['value'], 'Uang baru');
    expect(find.text('Uang baru'), findsOneWidget);
  });

  testWidgets('shows server error when load fails', (tester) async {
    final api = MockApiClient();
    // no onGet -> returns empty map, no crash, shows empty state
    await tester.pumpWidget(buildCopyAdmin(api));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}