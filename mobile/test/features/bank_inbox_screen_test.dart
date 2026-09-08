import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/features/bank_inbox/ui/bank_inbox_screen.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

const _channel = MethodChannel('com.filla.wealthtrack/bank_capture');

Widget buildInbox(MockApiClient api) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => api),
      ),
      secureStorageProvider.overrideWithProvider(
        Provider<SecureStorage>((ref) => MockSecureStorage()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const BankInboxScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    initTestSecureStorage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'isEnabled':
          return true;
        case 'drain':
          return <dynamic>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('shows empty copy when no drafts', (tester) async {
    final api = MockApiClient();
    api.onGet('/bank-inbox', {'items': [], 'pending_count': 0});
    await tester.pumpWidget(buildInbox(api));
    await tester.pump();
    await tester.pump();
    expect(find.text('Belum ada draf dari notifikasi bank'), findsOneWidget);
  });

  testWidgets('lists draft and Catat posts confirm', (tester) async {
    final api = MockApiClient();
    api.onGet('/bank-inbox', {
      'items': [
        {
          'id': 7,
          'bank': 'bca',
          'package': 'com.bca',
          'title': 'BCA',
          'text': 'Debit Rp50.000',
          'posted_at': '2026-09-08T10:00:00Z',
          'amount': 50000,
          'type': 'expense',
          'merchant': 'QRIS GRAB',
          'parsed': true,
          'status': 'pending',
          'transaction_id': null,
          'created_at': '2026-09-08T10:00:01Z',
        }
      ],
      'pending_count': 1,
    });
    api.onPost('/bank-inbox/7/confirm', {
      'id': 7,
      'status': 'confirmed',
      'transaction_id': 99,
      'parsed': true,
      'amount': 50000,
      'bank': 'bca',
      'package': 'com.bca',
      'title': 'BCA',
      'text': 'Debit Rp50.000',
      'posted_at': '2026-09-08T10:00:00Z',
      'type': 'expense',
      'merchant': 'QRIS GRAB',
      'created_at': '2026-09-08T10:00:01Z',
    });
    await tester.pumpWidget(buildInbox(api));
    await tester.pump();
    await tester.pump();
    expect(find.text('QRIS GRAB'), findsOneWidget);
    await tester.tap(find.text('Catat'));
    await tester.pump();
    await tester.pump();
    expect(api.lastPostPath, '/bank-inbox/7/confirm');
  });
}
