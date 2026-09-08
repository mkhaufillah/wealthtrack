import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wealthtrack/features/categories/providers/category_provider.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

void main() {
  group('CategoryManagementNotifier', () {
    late MockApiClient mockApi;
    late ProviderContainer container;
    late CategoryManagementNotifier notifier;

    setUp(() {
      mockApi = MockApiClient();
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(mockApi),
      ]);
      notifier = container.read(categoryManagementProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is correct', () {
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
      expect(notifier.state.categories, isEmpty);
    });

    test('load populates categories', () async {
      mockApi.onGet('/categories', [
        {'id': 1, 'name': 'Makanan', 'type': 'expense', 'icon': 'a', 'is_default': true, 'keywords': []},
        {'id': 2, 'name': 'Gaji', 'type': 'income', 'icon': 'b', 'is_default': true, 'keywords': []},
      ]);
      await notifier.load();
      expect(notifier.state.isLoading, false);
      expect(notifier.state.categories.length, 2);
      expect(notifier.state.error, isNull);
      expect(mockApi.lastGetPath, '/categories');
    });

    test('create posts and reloads', () async {
      mockApi.onGet('/categories', []);
      mockApi.onPost('/categories', {});
      final ok = await notifier.create({'name': 'Kendaraan', 'type': 'expense', 'icon': 'car'});
      expect(ok, true);
      expect(mockApi.lastPostPath, '/categories');
      expect((mockApi.lastPostData as Map)['name'], 'Kendaraan');
    });

    test('update puts and reloads', () async {
      mockApi.onGet('/categories', []);
      mockApi.onPut('/categories/5', {});
      final ok = await notifier.update(5, {'name': 'Baru'});
      expect(ok, true);
      expect(mockApi.lastPutPath, '/categories/5');
    });

    test('delete calls DELETE and reloads', () async {
      mockApi.onGet('/categories', []);
      mockApi.onDelete('/categories/5');
      final ok = await notifier.delete(5);
      expect(ok, true);
      expect(mockApi.lastDeletePath, '/categories/5');
    });

    test('delete failure surfaces error and returns false', () async {
      mockApi.onGet('/categories', []);
      // not registered -> MockApiClient throws Exception on delete
      final ok = await notifier.delete(999);
      expect(ok, false);
      expect(notifier.state.error, isNotNull);
    });
  });
}