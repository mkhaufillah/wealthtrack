import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/transactions/providers/transaction_provider.dart';
import '../../core/ui/copy_fallback.dart';
import '../../core/ui/app_icons.dart';
import '../providers/theme_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/transactions')) return 1;
    if (location.startsWith('/budgets')) return 2;
    if (location.startsWith('/reports')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    final index = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: index,
        onTap: (i) {
          switch (i) {
            case 0: context.go('/home');
            case 1: context.go('/transactions');
            case 2: context.go('/budgets');
            case 3: context.go('/reports');
            case 4: context.go('/profile');
          }
        },
        items: [
          BottomNavigationBarItem(icon: AppIcon(AppIcons.home, size: 22), label: t('nav.dashboard')),
          BottomNavigationBarItem(icon: AppIcon(AppIcons.receipt, size: 22), label: t('nav.transactions')),
          BottomNavigationBarItem(icon: AppIcon(AppIcons.wallet, size: 22), label: t('nav.budgets')),
          BottomNavigationBarItem(icon: AppIcon(AppIcons.chart, size: 22), label: t('nav.reports')),
          BottomNavigationBarItem(icon: AppIcon(AppIcons.user, size: 22), label: t('nav.profile')),
        ],
      ),
      floatingActionButton: index <= 1 && (index == 0 || !ref.watch(isCategoryFilterSheetOpenProvider))
          ? FloatingActionButton(
              onPressed: () => context.push('/transactions/add'),
              child: AppIcon(AppIcons.add, size: 24),
            )
          : null,
    );
  }
}
