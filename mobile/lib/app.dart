import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/home/ui/home_screen.dart';
import 'features/transactions/ui/transaction_list_screen.dart';
import 'features/transactions/ui/add_transaction_screen.dart';
import 'features/transactions/models/transaction_model.dart';
import 'features/profile/ui/profile_screen.dart';
import 'features/reports/ui/reports_screen.dart';
import 'features/budgets/ui/budgets_screen.dart';
import 'features/ai/ui/ai_advisor_screen.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/widgets/app_scaffold.dart';

final _isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final loggedIn = ref.watch(_isAuthenticatedProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
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
          GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/transactions/add',
        builder: (_, state) => AddTransactionScreen(
          editTransaction: state.extra is TransactionModel ? state.extra as TransactionModel : null,
        ),
      ),
      GoRoute(
        path: '/ai/advise',
        builder: (_, __) => const AiAdvisorScreen(),
      ),
    ],
  );
});

class WealthTrackApp extends ConsumerStatefulWidget {
  const WealthTrackApp({super.key});

  @override
  ConsumerState<WealthTrackApp> createState() => _WealthTrackAppState();
}

class _WealthTrackAppState extends ConsumerState<WealthTrackApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    ref.read(authProvider.notifier).checkAuth().then((_) {
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => ui.PlatformDispatcher.instance.platformBrightness,
    };
    AppColors.sync(brightness);
    return MaterialApp.router(
      title: 'WealthTrack',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
