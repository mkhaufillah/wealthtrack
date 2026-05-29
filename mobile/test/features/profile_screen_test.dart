import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/profile/ui/profile_screen.dart';
import 'package:wealthtrack/features/auth/providers/auth_provider.dart';
import 'package:wealthtrack/features/auth/data/auth_repository.dart';
import 'package:wealthtrack/features/auth/models/user_model.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import 'package:wealthtrack/core/network/api_client.dart';
import 'package:wealthtrack/core/storage/secure_storage.dart';
import '../helpers/mocks.dart';

class _MockAuthRepo extends AuthRepository {
  _MockAuthRepo() : super(MockApiClient());
}

Widget buildProfileApp({
  UserModel? user,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWithProvider(
        StateNotifierProvider<AuthNotifier, AuthState>((ref) {
          return AuthNotifier(_MockAuthRepo(), MockSecureStorage(), MockApiClient())
            ..state = AuthState(
              status: AuthStatus.authenticated,
              user: user ??
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
        Provider<ApiClient>((ref) => MockApiClient()),
      ),
      secureStorageProvider.overrideWithProvider(
        Provider<SecureStorage>((ref) => MockSecureStorage()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const ProfileScreen(),
    ),
  );
}

void main() {
  setUp(() => initTestSecureStorage());

  group('ProfileScreen', () {
    testWidgets('shows Profile title in app bar', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('shows user display name from auth state', (tester) async {
      await tester.pumpWidget(buildProfileApp(
        user: UserModel(
          id: 1,
          username: 'johndoe',
          displayName: 'John Doe',
          role: 'user',
        ),
      ));
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('shows username with @ prefix', (tester) async {
      await tester.pumpWidget(buildProfileApp(
        user: UserModel(
          id: 1,
          username: 'johndoe',
          displayName: 'John Doe',
          role: 'user',
        ),
      ));
      expect(find.text('@johndoe'), findsOneWidget);
    });

    testWidgets('shows user role', (tester) async {
      await tester.pumpWidget(buildProfileApp(
        user: UserModel(
          id: 1,
          username: 'admin',
          displayName: 'Admin User',
          role: 'admin',
        ),
      ));
      expect(find.text('admin'), findsOneWidget);
    });

    testWidgets('shows Edit Profile menu item', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('shows Change Password menu item', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('shows AI Financial Advisor menu item', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // Scroll down to find AI Financial Advisor
      await tester.dragUntilVisible(
        find.text('AI Financial Advisor'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('AI Financial Advisor'), findsOneWidget);
    });

    testWidgets('shows Account Settings section header', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      expect(find.text('Account Settings'), findsOneWidget);
    });

    testWidgets('shows Features section header', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // Scroll to find Features section
      await tester.dragUntilVisible(
        find.text('Features'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Features'), findsOneWidget);
    });

    testWidgets('shows Appearance section with theme options', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // Scroll down to Appearance section
      await tester.dragUntilVisible(
        find.text('Follow System'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Follow System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('shows Logout and Delete Account in Account Actions',
        (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // Scroll down to Account Actions section
      await tester.dragUntilVisible(
        find.text('Delete Account'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      expect(find.text('Account Actions'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('shows household section with Join Household and Create New buttons',
        (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // After post-frame callback, household loads from mock API (returns empty)
      // so Join Household and Create New are shown
      await tester.pump();
      expect(find.text('Household'), findsOneWidget);
      expect(find.text('Join Household'), findsOneWidget);
      expect(find.text('Create New'), findsOneWidget);
    });

    testWidgets('shows app version at bottom', (tester) async {
      await tester.pumpWidget(buildProfileApp());
      // Scroll down to version text
      await tester.dragUntilVisible(
        find.text('WealthTrack v1.0.0'),
        find.byType(ListView),
        const Offset(0, -500),
      );
      expect(find.text('WealthTrack v1.0.0'), findsOneWidget);
    });
  });
}
