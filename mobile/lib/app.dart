import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/home/ui/home_screen.dart';
import 'features/transactions/ui/transaction_list_screen.dart';
import 'features/transactions/ui/add_transaction_screen.dart';
import 'shared/widgets/app_scaffold.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final loggingIn = state.matchedLocation == '/login';
      final registering = state.matchedLocation == '/register';

      if (!loggedIn && !loggingIn && !registering) return '/login';
      if (loggedIn && (loggingIn || registering)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const TransactionListScreen(),
          ),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsPlaceholder()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePlaceholder()),
        ],
      ),
      GoRoute(
        path: '/transactions/add',
        builder: (_, __) => const AddTransactionScreen(),
      ),
    ],
  );
});

class WealthTrackApp extends ConsumerWidget {
  const WealthTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'WealthTrack',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class ReportsPlaceholder extends StatelessWidget {
  const ReportsPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Reports — Coming soon'));
}

class ProfilePlaceholder extends StatelessWidget {
  const ProfilePlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Profile — Coming soon'));
}
