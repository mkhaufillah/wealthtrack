import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/features/auth/ui/onboarding_screen.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/shared/providers/onboarding_provider.dart';
import '../helpers/mocks.dart';

Widget buildOnboardingApp({MockSecureStorage? storage}) {
  final store = storage ?? MockSecureStorage();
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithProvider(
        Provider<SecureStorage>((ref) => store),
      ),
      apiClientProvider.overrideWithProvider(
        Provider<ApiClient>((ref) => MockApiClient()),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, __) => const OnboardingScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('login-ok')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  testWidgets('first page shows language pick and illustration', (tester) async {
    await tester.pumpWidget(buildOnboardingApp());
    await tester.pump();
    expect(find.text('Pilih bahasa'), findsOneWidget);
    expect(find.text('Choose a language'), findsOneWidget);
    expect(find.text('Indonesia'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Lanjut'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('next slides then start marks onboarding done', (tester) async {
    final storage = MockSecureStorage();
    await tester.pumpWidget(buildOnboardingApp(storage: storage));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Catat duit, tanpa drama'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Yuk mulai'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(await storage.getSecure(kOnboardingDoneKey), '1');
  });
}
