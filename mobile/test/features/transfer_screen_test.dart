import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/transactions/ui/transfer_screen.dart';
import 'package:wealthtrack/features/transactions/providers/transfer_provider.dart';
import 'package:wealthtrack/features/transactions/data/transaction_repository.dart';
import 'package:wealthtrack/features/auth/providers/auth_provider.dart';
import 'package:wealthtrack/features/auth/data/auth_repository.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import '../helpers/mocks.dart';

class _MockTxnRepo extends TransactionRepository {
  _MockTxnRepo() : super(MockApiClient());
}

class _MockAuthRepo extends AuthRepository {
  _MockAuthRepo() : super(MockApiClient());
}

/// Helper to register household members mock on an API client.
MockApiClient _setupMockHousehold(MockApiClient api, {List<Map<String, dynamic>> members = const []}) {
  api.onGet('/households/me', {
    'members': members,
  });
  return api;
}

Widget buildTransferApp({
  UserModel? currentUser,
  MockApiClient? apiClient,
  bool isSubmitting = false,
  String? error,
}) {
  final mockApi = apiClient ?? MockApiClient();

  return ProviderScope(
    overrides: [
      transferBalanceProvider.overrideWithProvider(
        StateNotifierProvider<TransferBalanceNotifier, TransferBalanceState>(
            (ref) {
          final notifier =
              TransferBalanceNotifier(_MockTxnRepo(), mockApi);
          notifier.state = TransferBalanceState(
            isSubmitting: isSubmitting,
            error: error,
          );
          return notifier;
        }),
      ),
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          return AuthNotifier(
                  _MockAuthRepo(), MockSecureStorage(), MockApiClient())
            ..state = AuthState(
              status: AuthStatus.authenticated,
              user: currentUser ??
                  UserModel(
                    id: 1,
                    username: 'testuser',
                    displayName: 'Test User',
                    role: 'user',
                  ),
              isAuthenticated: true,
            );
        }),
      ),
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => mockApi),
      ),
      secureStorageProvider.overrideWithProvider(
        Provider<SecureStorage>((ref) => MockSecureStorage()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const TransferBalanceScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  group('TransferBalanceScreen', () {
    testWidgets('shows Transfer Balance title in app bar', (tester) async {
      await tester.pumpWidget(buildTransferApp());
      expect(find.text('Transfer Balance'), findsOneWidget);
    });

    testWidgets('shows loading indicator while loading members',
        (tester) async {
      await tester.pumpWidget(buildTransferApp());
      // Initially _loadingMembers is true, CircularProgressIndicator shown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no household members',
        (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: []);
      await tester.pumpWidget(buildTransferApp(apiClient: mockApi));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.group_off), findsOneWidget);
      expect(find.text('No household members available'), findsOneWidget);
    });

    testWidgets('shows sender card when members available', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(
        apiClient: mockApi,
        currentUser: UserModel(
          id: 1,
          username: 'filla',
          displayName: 'Filla',
          role: 'user',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('From'), findsOneWidget);
      expect(find.text('Filla'), findsOneWidget);
    });

    testWidgets('shows date picker card', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(apiClient: mockApi));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.byIcon(Icons.edit_calendar), findsOneWidget);
    });

    testWidgets('shows recipients section header', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(apiClient: mockApi));
      await tester.pumpAndSettle();

      expect(find.text('Recipients'), findsOneWidget);
    });

    testWidgets('pre-selects first available recipient', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(
        apiClient: mockApi,
        currentUser: UserModel(
          id: 1,
          username: 'filla',
          displayName: 'Filla',
          role: 'user',
        ),
      ));
      await tester.pumpAndSettle();

      // Nahda should be auto-selected as recipient
      expect(find.text('Nahda'), findsOneWidget);
    });

    testWidgets('shows Send Transfer button', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(apiClient: mockApi));
      await tester.pumpAndSettle();

      expect(find.text('Send Transfer'), findsOneWidget);
    });

    testWidgets('shows error display when transfer fails', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(
        apiClient: mockApi,
        error: 'Insufficient balance',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Insufficient balance'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows Processing state on Send Transfer button when submitting',
        (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(
        apiClient: mockApi,
        isSubmitting: true,
      ));
      // Use pump() instead of pumpAndSettle() to avoid timer timeouts
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Processing...'), findsOneWidget);
      // FilledButton should be disabled (onPressed: null) when submitting
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Processing...'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows amount field for recipient', (tester) async {
      final mockApi = _setupMockHousehold(MockApiClient(), members: [
        {'user_id': 2, 'display_name': 'Nahda', 'role': 'member'},
      ]);

      await tester.pumpWidget(buildTransferApp(
        apiClient: mockApi,
        currentUser: UserModel(
          id: 1,
          username: 'filla',
          displayName: 'Filla',
          role: 'user',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
