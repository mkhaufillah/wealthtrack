import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:wealthtrack/core/ui/app_icons.dart';
import 'package:wealthtrack/core/ui/brand_mark.dart';
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
    testWidgets('shows Hai lagi branding', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.text('Hai lagi'), findsOneWidget);
      expect(find.text('Catat duit, tanpa drama'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.byType(BrandMark), findsOneWidget);
    });

    testWidgets('login mark uses light plate asset', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      final image = tester.widget<Image>(
        find.descendant(of: find.byType(BrandMark), matching: find.byType(Image)),
      );
      expect((image.image as AssetImage).assetName, 'assets/logo_login_light.jpg');
    });

    testWidgets('login mark uses dark plate asset', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWithProvider(
              StateNotifierProvider<AuthNotifier, AuthState>((ref) {
                final notifier = AuthNotifier(
                    MockAuthRepository(), MockSecureStorage(), MockApiClient());
                notifier.state = const AuthState(status: AuthStatus.initial);
                return notifier;
              }),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const LoginScreen(),
          ),
        ),
      );
      final image = tester.widget<Image>(
        find.descendant(of: find.byType(BrandMark), matching: find.byType(Image)),
      );
      expect((image.image as AssetImage).assetName, 'assets/logo_login_dark.jpg');
    });

    testWidgets('text field icons stay compact', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      final fieldIcons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .where((w) =>
              w.icon == HugeIcons.strokeRoundedUser ||
              w.icon == HugeIcons.strokeRoundedShield01)
          .toList();
      expect(fieldIcons, isNotEmpty);
      expect(fieldIcons.every((w) => w.size <= 16), isTrue);
    });

    testWidgets('shows username and password fields', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('shows Login button and Register link', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.text('Masuk'), findsOneWidget);
      expect(find.text('Belum punya akun? Daftar dulu'), findsOneWidget);
    });

    testWidgets('shows error message when present', (tester) async {
      await tester.pumpWidget(buildLoginApp(error: 'Invalid credentials'));
      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('validates empty fields', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('Minimal 3 huruf'), findsOneWidget);
      expect(find.text('Minimal 6 karakter'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('shows Register title', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Yuk daftar'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
    });

    testWidgets('shows five input fields', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      // Email, username, display_name, password, confirm_password
      expect(find.byType(TextFormField), findsNWidgets(5));
    });

    testWidgets('shows Register button and Login link', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      expect(find.text('Kirim kode'), findsOneWidget);
      expect(find.text('Sudah punya akun? Masuk aja'), findsOneWidget);
    });

    testWidgets('validates form fields', (tester) async {
      await tester.pumpWidget(buildRegisterApp());

      // First fill email and send OTP
      await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Kirim kode'));
      await tester.pumpAndSettle();

      // Now OTP is sent, OTP field appears (6th TextFormField)
      // Leave other fields empty and tap Register
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Daftar'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Daftar'));
      await tester.pumpAndSettle();

      expect(find.text('Minimal 3 huruf'), findsOneWidget);
      expect(find.text('Nama tampilan wajib diisi'), findsOneWidget);
      expect(find.text('Minimal 6 karakter'), findsOneWidget);
      expect(find.text('Valid email required'), findsNothing); // email already filled
    });
  });

  group('LoginScreen Eye Icon', () {
    testWidgets('shows visibility icon on password field', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedView), findsNothing);
    });

    testWidgets('toggles password visibility on tap', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      // Tap the eye icon
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash));
      await tester.pump();
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedView), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash), findsNothing);
    });

    testWidgets('toggles back to hidden on second tap', (tester) async {
      await tester.pumpWidget(buildLoginApp());
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash));
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedView));
      await tester.pump();
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash), findsOneWidget);
    });
  });

  group('RegisterScreen Eye Icon', () {
    testWidgets('shows visibility icon on password fields', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      // Both password fields have independent eye icons
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash), findsNWidgets(2));
    });

    testWidgets('toggles password visibility independently', (tester) async {
      await tester.pumpWidget(buildRegisterApp());
      // Toggle only password eye
      await tester.tap(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash).first);
      await tester.pump();
      // Password field toggled to visible, confirm stayed obscured
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedView), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedViewOffSlash), findsOneWidget);
    });
  });
}
