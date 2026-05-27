import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/auth/providers/auth_provider.dart';
import 'package:wealthtrack/features/auth/ui/login_screen.dart';
import 'package:wealthtrack/features/auth/ui/register_screen.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/features/auth/models/token_model.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import '../helpers/mocks.dart';

// Minimal mock repo to satisfy AuthNotifier constructor
class MockAuthRepository {
  Future<TokenModel> login(String u, String p) async =>
      TokenModel(accessToken: 'mock', tokenType: 'bearer', expiresIn: 3600);
  Future<UserModel> register(String u, String d, String p) async =>
      UserModel(id: 1, username: u, displayName: d, role: 'user');
  Future<UserModel> getMe() async =>
      UserModel(id: 1, username: 'mock', displayName: 'Mock', role: 'user');
}

Widget buildLoginApp({AuthStatus status = AuthStatus.initial, String? error}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          final notifier = AuthNotifier(MockAuthRepository(), MockSecureStorage());
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
          final notifier = AuthNotifier(MockAuthRepository(), MockSecureStorage());
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

    testWidgets('shows Quick login as Filla button', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.text('Quick login as Filla'), findsOneWidget);
    });

    testWidgets('shows error message when present', (tester) async {
      await tester.pumpWidget(buildLoginApp(error: 'Invalid credentials'));
      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('validates empty fields', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('shows Register title', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('shows three input fields', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('shows Register button and Login link', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Register'), findsOneWidget);
      expect(find.text('Already have an account? Login'), findsOneWidget);
    });

    testWidgets('validates username length', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.text('Min 3 characters'), findsOneWidget);
      expect(find.text('Display name is required'), findsOneWidget);
      expect(find.text('Min 6 characters'), findsOneWidget);
    });
  });
}
