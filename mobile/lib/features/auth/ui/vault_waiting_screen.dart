import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/brand_mark.dart';
import '../../../core/ui/app_icons.dart';
import '../providers/auth_provider.dart';

/// Friendly gate while a joined member waits for the household owner to
/// share the vault key (gembok). The app auto-picks the key up from the
/// share-inbox, so this page usually unlocks itself within seconds of the
/// owner pressing "Bagikan gembok".
class VaultWaitingScreen extends ConsumerStatefulWidget {
  const VaultWaitingScreen({super.key});

  @override
  ConsumerState<VaultWaitingScreen> createState() => _VaultWaitingScreenState();
}

class _VaultWaitingScreenState extends ConsumerState<VaultWaitingScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      await ref.read(authProvider.notifier).refreshVaultKey();
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _check,
          color: AppColors.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
            children: [
              const SizedBox(height: 24),
              const Center(child: BrandMark(size: 110)),
              const SizedBox(height: 28),
              Text(
                t('hh.wait_key_title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t('hh.wait_key_body'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    AppIcon(AppIcons.shield, size: 22, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t('hh.wait_key_note'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t('hh.wait_key_pull'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}