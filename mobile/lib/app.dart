import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/home/ui/home_screen.dart';
import 'features/transactions/ui/transaction_list_screen.dart';
import 'features/transactions/ui/add_transaction_screen.dart';
import 'features/transactions/ui/transfer_screen.dart';
import 'features/transactions/models/transaction_model.dart';
import 'features/profile/ui/profile_screen.dart';
import 'features/reports/ui/reports_screen.dart';
import 'features/budgets/ui/budgets_screen.dart';
import 'features/ai/ui/ai_advisor_screen.dart';
import 'features/categories/ui/category_management_screen.dart';
import 'features/debt/ui/debt_home_screen.dart';
import 'features/debt/kpr/ui/kpr_list_screen.dart';
import 'features/debt/kpr/ui/kpr_form_screen.dart';
import 'features/debt/kpr/ui/kpr_detail_screen.dart';
import 'features/debt/credit_card/ui/credit_card_list_screen.dart';
import 'features/debt/credit_card/ui/credit_card_form_screen.dart';
import 'features/debt/credit_card/ui/credit_card_detail_screen.dart';
import 'features/debt/credit_card/ui/add_installment_screen.dart';
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
            builder: (_, state) => TransactionListScreen(
              preSelectedCategoryId: state.extra is int ? state.extra as int : null,
            ),
          ),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/debt',
        builder: (_, __) => const DebtHomeScreen(),
      ),
      GoRoute(
        path: '/debt/kpr',
        builder: (_, __) => const KPRListScreen(),
      ),
      GoRoute(
        path: '/debt/kpr/new',
        builder: (_, __) => const KPRFormScreen(),
      ),
      GoRoute(
        path: '/debt/kpr/:id',
        builder: (_, state) => KPRDetailScreen(
          simulationId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/debt/credit-cards',
        builder: (_, __) => const CreditCardListScreen(),
      ),
      GoRoute(
        path: '/debt/credit-cards/new',
        builder: (_, __) => const CreditCardFormScreen(),
      ),
      GoRoute(
        path: '/debt/credit-cards/:id',
        builder: (_, state) => CreditCardDetailScreen(
          cardId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/debt/credit-cards/:id/installments/new',
        builder: (_, state) => AddInstallmentScreen(
          cardId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/transactions/add',
        builder: (_, state) => AddTransactionScreen(
          editTransaction: state.extra is TransactionModel ? state.extra as TransactionModel : null,
          autoScan: state.extra is Map ? (state.extra as Map)['autoScan'] == true : false,
        ),
      ),
      GoRoute(
        path: '/transactions/transfer',
        builder: (_, __) => const TransferBalanceScreen(),
      ),
      GoRoute(
        path: '/ai/advise',
        builder: (_, __) => const AiAdvisorScreen(),
      ),
      GoRoute(
        path: '/categories/manage',
        builder: (_, __) => const CategoryManagementScreen(),
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
  static const _widgetChannel = MethodChannel('com.filla.wealthtrack/widget');

  @override
  void initState() {
    super.initState();
    _widgetChannel.setMethodCallHandler(_handleWidgetNavigation);
    ref.read(authProvider.notifier).checkAuth().then((_) {
      if (mounted) setState(() => _initialized = true);
      _checkPendingWidgetAction();
    });
  }

  @override
  void dispose() {
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleWidgetNavigation(MethodCall call) async {
    if (call.method != 'navigate') return;
    final action = call.arguments as String?;
    final router = ref.read(goRouterProvider);
    switch (action) {
      case 'add_transaction':
        router.go('/transactions/add');
      case 'scan_receipt':
        router.go('/transactions/add', extra: <String, dynamic>{'autoScan': true});
    }
  }

  Future<void> _checkPendingWidgetAction() async {
    try {
      final pending = await _widgetChannel.invokeMethod<String>('getPendingAction');
      if (pending != null && mounted) {
        final router = ref.read(goRouterProvider);
        if (pending == 'add_transaction') {
          router.go('/transactions/add');
        } else if (pending == 'scan_receipt') {
          router.go('/transactions/add', extra: <String, dynamic>{'autoScan': true});
        }
      }
    } catch (_) {}
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
