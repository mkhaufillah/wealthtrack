import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/auth/providers/auth_provider.dart';
import 'package:wealthtrack/features/auth/ui/login_screen.dart';
import 'package:wealthtrack/features/auth/ui/register_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import '../helpers/mocks.dart';

Widget buildLoginApp({AuthStatus status = AuthStatus.initial, String? error}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          final notifier = AuthNotifier(MockAuthRepository(), MockSecureStorage(), MockApiClient());
          notifier.state = AuthState(status: status, error: error);
          return notifier;
        }),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const LoginScreen(),
    ),
  );
}

Widget buildRegisterApp({AuthStatus status = AuthStatus.initial}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          final notifier = AuthNotifier(MockAuthRepository(), MockSecureStorage(), MockApiClient());
          notifier.state = AuthState(status: status);
          return notifier;
        }),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const RegisterScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  group('LoginScreen', () {
    testWidgets('shows WealthTrack branding', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.text('WealthTrack'), findsOneWidget);
    });

    testWidgets('shows username and password fields', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('shows Login button and Register link', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.text('Login'), findsOneWidget);
      expect(find.text("Don't have an account? Register"), findsOneWidget);
    });

    testWidgets('shows error message when present', (tester) async {
      await tester.pumpWidget(buildLoginApp(error: 'Invalid credentials'));
      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('validates empty fields', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Min 3 characters'), findsOneWidget);
      expect(find.text('Min 6 characters'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('shows Register title', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Register'), findsAtLeast(1));
    });

    testWidgets('shows three input fields', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('shows Register button and Login link', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Register'), findsAtLeast(1));
      expect(find.text('Already have an account? Login'), findsOneWidget);
    });

    testWidgets('validates username length', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
      await tester.pumpAndSettle();
      expect(find.text('Min 3 characters'), findsOneWidget);
      expect(find.text('Display name is required'), findsOneWidget);
      expect(find.text('Min 6 characters'), findsOneWidget);
    });
  });

  group('LoginScreen Eye Icon', () {
    testWidgets('shows visibility icon on password field', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('toggles password visibility on tap', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      // Tap the eye icon
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });

    testWidgets('toggles back to hidden on second tap', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('RegisterScreen Eye Icon', () {
    testWidgets('shows visibility icon on password field', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('toggles password visibility', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });
}
