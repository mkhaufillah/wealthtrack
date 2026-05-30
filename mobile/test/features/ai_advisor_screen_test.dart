import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/ai/ui/ai_advisor_screen.dart';
import 'package:wealthtrack/features/auth/providers/auth_provider.dart';
import 'package:wealthtrack/features/auth/data/auth_repository.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../helpers/mocks.dart';

/// Helper to build the AI Advisor screen with proper mocks.
Widget buildAiAdvisorApp({
  UserModel? currentUser,
  MockApiClient? apiClient,
  bool overrideAuth = true,
}) {
  final mockApi = apiClient ?? MockApiClient();

  final overrides = <Override>[
    apiClientProvider.overrideWithProvider(
      Provider<ApiClient>((ref) => mockApi),
    ),
    secureStorageProvider.overrideWithProvider(
      Provider<SecureStorage>((ref) => MockSecureStorage()),
    ),
  ];

  if (overrideAuth) {
    overrides.add(
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          return AuthNotifier(
                  MockAuthRepository(), MockSecureStorage(), MockApiClient())
            ..state = AuthState(
              status: AuthStatus.authenticated,
              user: currentUser ??
                  UserModel(
                    id: 1,
                    username: 'filla',
                    displayName: 'Filla',
                    role: 'user',
                  ),
              isAuthenticated: true,
            );
        }),
      ),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      home: const AiAdvisorScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  group('AiAdvisorScreen', () {
    testWidgets('shows AI Financial Advisor title in app bar',
        (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.pump();
      expect(find.text('AI Financial Advisor'), findsOneWidget);
    });

    testWidgets('shows disclaimer text', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.pump();
      expect(
        find.text(
          'AI-generated advice, not certified financial planning',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows loading indicator while history loads',
        (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows input text field with hint', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Ask about your finances...'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows send button', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('shows Flash model toggle for admin user', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp(
        currentUser: UserModel(
          id: 1,
          username: 'filla',
          displayName: 'Filla',
          role: 'admin',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Flash'), findsOneWidget);
    });

    testWidgets('toggle switches to Advanced for admin user',
        (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp(
        currentUser: UserModel(
          id: 1,
          username: 'filla',
          displayName: 'Filla',
          role: 'admin',
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Flash'));
      await tester.pump();

      expect(find.text('Advanced'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('model toggle hidden for non-user-1', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp(
        currentUser: UserModel(
          id: 2,
          username: 'nahda',
          displayName: 'Nahda',
          role: 'member',
        ),
      ));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Flash'), findsNothing);
      expect(find.text('Advanced'), findsNothing);
    });

    testWidgets('clear chat button not visible when no messages',
        (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('empty message does not send', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap send with empty text field
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Text field hint should still show (empty state)
      expect(
        find.text('Ask about your finances...'),
        findsOneWidget,
      );
    });

    testWidgets('send button has send icon', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('text field has send textInputAction', (tester) async {
      await tester.pumpWidget(buildAiAdvisorApp());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textInputAction, TextInputAction.send);
    });
  });
}
