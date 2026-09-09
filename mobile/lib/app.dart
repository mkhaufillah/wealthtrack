import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/ui_config.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/auth/ui/onboarding_screen.dart';
import 'features/home/ui/home_screen.dart';
import 'features/transactions/ui/transaction_list_screen.dart';
import 'features/transactions/ui/add_transaction_screen.dart';
import 'features/transactions/ui/transfer_screen.dart';
import 'features/transactions/models/transaction_model.dart';
import 'features/profile/ui/profile_screen.dart';
import 'features/profile/ui/copy_admin_screen.dart';
import 'features/profile/ui/config_admin_screen.dart';
import 'features/reports/ui/reports_screen.dart';
import 'features/budgets/ui/budgets_screen.dart';
import 'features/ai/ui/ai_advisor_screen.dart';
import 'features/categories/ui/category_management_screen.dart';
import 'features/debt/ui/debt_home_screen.dart';
import 'features/debt/kpr/ui/kpr_list_screen.dart';
import 'features/debt/kpr/ui/kpr_form_screen.dart';
import 'features/debt/kpr/ui/kpr_detail_screen.dart';
import 'features/debt/kpr/ui/kpr_extra_payment_screen.dart';
import 'features/debt/credit_card/ui/credit_card_list_screen.dart';
import 'features/debt/credit_card/ui/credit_card_form_screen.dart';
import 'features/debt/credit_card/ui/credit_card_detail_screen.dart';
import 'features/debt/credit_card/ui/add_installment_screen.dart';
import 'features/bank_inbox/ui/bank_inbox_screen.dart';
import 'features/bank_inbox/ui/bank_listen_apps_screen.dart';
import 'features/bank_inbox/data/bank_capture.dart';
import 'shared/providers/app_providers.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/providers/locale_provider.dart';
import 'shared/providers/onboarding_provider.dart';
import 'shared/widgets/app_scaffold.dart';

final _isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final loggedIn = ref.watch(_isAuthenticatedProvider);
  final onboarded = ref.watch(onboardingProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login';
      final registering = loc == '/register';
      final onboarding = loc == '/onboarding';

      if (onboarded == null) return null;

      if (loggedIn) {
        if (loggingIn || registering || onboarding) return '/home';
        return null;
      }

      if (onboarded != true && !onboarding) return '/onboarding';
      if (onboarded == true && onboarding) return '/login';
      if (!loggingIn && !registering && !onboarding) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
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
        path: '/debt/kpr/:id/extra-payment',
        builder: (_, state) => KPRExtraPaymentScreen(
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
      GoRoute(
        path: '/profile/copy',
        builder: (_, __) => const CopyAdminScreen(),
      ),
      GoRoute(
        path: '/profile/config',
        builder: (_, __) => const ConfigAdminScreen(),
      ),
      GoRoute(
        path: '/bank-inbox',
        builder: (_, __) => const BankInboxScreen(),
      ),
      GoRoute(
        path: '/bank-inbox/listen',
        builder: (_, __) => const BankListenAppsScreen(),
      ),
    ],
  );
});

class WealthTrackApp extends ConsumerStatefulWidget {
  const WealthTrackApp({super.key});

  @override
  ConsumerState<WealthTrackApp> createState() => _WealthTrackAppState();
}

class _WealthTrackAppState extends ConsumerState<WealthTrackApp> with WidgetsBindingObserver {
  bool _initialized = false;
  static const _widgetChannel = MethodChannel('com.filla.wealthtrack/widget');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetChannel.setMethodCallHandler(_handleWidgetNavigation);
    // Load live copy/theme/format from GET /ui/bootstrap (DB via Redis).
    unawaited(ref.read(uiConfigProvider.notifier).load());
    ref.read(authProvider.notifier).checkAuth().then((_) {
      if (mounted) setState(() => _initialized = true);
      _checkPendingWidgetAction();
      if (ref.read(authProvider).isAuthenticated) {
        unawaited(BankCapture.requestNotify());
        unawaited(BankCapture.applyPendingAction(ref.read(apiClientProvider)));
      }
    }).catchError((_) {
      // Safety net: if checkAuth throws unexpectedly, still release the loading screen
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(authProvider).isAuthenticated) {
      unawaited(BankCapture.applyPendingAction(ref.read(apiClientProvider)));
    }
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
    if (!_initialized || ref.watch(onboardingProvider) == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: ref.read(localeProvider.notifier).materialLocale,
        supportedLocales: const [Locale('id'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final router = ref.watch(goRouterProvider);
    // Watch bootstrap state so any live copy/theme/format update (admin PUT)
    // rebuilds the whole tree with the fresh values from /ui/bootstrap.
    ref.watch(uiConfigProvider);
    final themeMode = ref.watch(themeModeProvider);
    final uiLocale = ref.watch(localeProvider);
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => ui.PlatformDispatcher.instance.platformBrightness,
    };
    AppColors.sync(brightness);
    return MaterialApp.router(
      title: 'WealthTrack',
      locale: uiLocale == 'en-US' ? const Locale('en') : const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
