import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/transactions/providers/transaction_provider.dart';
import '../helpers/mocks.dart';

void main() {
  late MockApiClient mockApi;
  late TransactionListNotifier notifier;

  setUp(() {
    initTestSecureStorage();
    mockApi = MockApiClient();
    mockApi.onGet('/categories', []);
    mockApi.onGet('/transactions', {
      'data': <dynamic>[],
      'meta': {'total': 0, 'page': 1, 'per_page': 20, 'total_pages': 0},
    });
    notifier = TransactionListNotifier(TransactionRepository(mockApi), mockApi);
  });

  group('date filter', () {
    test('setDateFilter sends date_from and date_to', () async {
      await notifier.setDateFilter(from: '2026-08-01', to: '2026-08-31');

      expect(notifier.state.dateFrom, '2026-08-01');
      expect(notifier.state.dateTo, '2026-08-31');
      expect(mockApi.lastGetPath, '/transactions');
      expect(mockApi.lastGetQuery?['date_from'], '2026-08-01');
      expect(mockApi.lastGetQuery?['date_to'], '2026-08-31');
    });

    test('clearDateFilter drops date params', () async {
      await notifier.setDateFilter(from: '2026-08-01', to: '2026-08-01');
      await notifier.clearDateFilter();

      expect(notifier.state.dateFrom, isNull);
      expect(notifier.state.dateTo, isNull);
      expect(mockApi.lastGetQuery?.containsKey('date_from') ?? false, isFalse);
      expect(mockApi.lastGetQuery?.containsKey('date_to') ?? false, isFalse);
    });
  });
}
