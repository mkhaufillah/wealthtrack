import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/categories/ui/category_management_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import '../helpers/mocks.dart';

Widget buildCatManage(MockApiClient api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => api),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const CategoryManagementScreen(),
    ),
  );
}

Map<String, dynamic> customCat(int id, String name) => {
      'id': id,
      'name': name,
      'type': 'expense',
      'icon': 'strokeRoundedCar01',
      'is_default': false,
      'keywords': [],
    };

void main() {
  testWidgets('shows expense + income sections and search field', (tester) async {
    final api = MockApiClient();
    api.onGet('/categories', [
      customCat(1, 'Makanan & Minuman'),
      {'id': 2, 'name': 'Gaji', 'type': 'income', 'icon': 'strokeRoundedMoneyBag01', 'is_default': true, 'keywords': []},
    ]);
    await tester.pumpWidget(buildCatManage(api));
    await tester.pumpAndSettle();

    expect(find.text('Pengeluaran'), findsOneWidget);
    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('Makanan & Minuman'), findsOneWidget);
    expect(find.text('Gaji'), findsOneWidget);
  });

  testWidgets('search filters list by name', (tester) async {
    final api = MockApiClient();
    api.onGet('/categories', [
      customCat(1, 'Makanan & Minuman'),
      customCat(2, 'Transportasi'),
    ]);
    await tester.pumpWidget(buildCatManage(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Makan');
    await tester.pumpAndSettle();

    expect(find.text('Makanan & Minuman'), findsOneWidget);
    expect(find.text('Transportasi'), findsNothing);
  });

  testWidgets('delete flow: confirmation then DELETE call', (tester) async {
    final api = MockApiClient();
    api.onGet('/categories', [customCat(99, 'Kendaraan')]);
    api.onDelete('/categories/99');
    await tester.pumpWidget(buildCatManage(api));
    await tester.pumpAndSettle();

    // open edit sheet
    await tester.tap(find.text('Kendaraan'));
    await tester.pumpAndSettle();

    // tap Hapus in the sheet
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    // confirmation dialog
    expect(find.text('Hapus kategori ini? Kategori yang sudah dipakai transaksi tetap aman dan gak bisa dihapus.'), findsOneWidget);
    // tap the confirm button inside the AlertDialog (not the sheet's Hapus)
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.widgetWithText(TextButton, 'Hapus')));
    await tester.pumpAndSettle();

    expect(api.lastDeletePath, '/categories/99');
  });

  testWidgets('default category not tappable for edit/delete', (tester) async {
    final api = MockApiClient();
    api.onGet('/categories', [
      {'id': 1, 'name': 'Gaji', 'type': 'income', 'icon': 'strokeRoundedMoneyBag01', 'is_default': true, 'keywords': []},
    ]);
    await tester.pumpWidget(buildCatManage(api));
    await tester.pumpAndSettle();

    // default tile has no delete/edit affordance; tapping does nothing
    await tester.tap(find.text('Gaji'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan'), findsNothing);
  });
}