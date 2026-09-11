import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/brand_mark.dart';
import '../../../core/ui/app_icons.dart';
import '../providers/auth_provider.dart';
import '../../../shared/providers/app_providers.dart';
import '../../profile/data/household_repository.dart';

/// Gate shown to authenticated users who have no household yet.
///
/// The vault DEK is wrapped per household, so a solo account cannot write
/// money rows until it either creates a household (own name) or joins one
/// via invite code. This screen makes that choice explicit instead of
/// letting every write fail with err.vault_required.
class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() =>
      _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  bool _busy = false;

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t('hh.create_new')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('hh.name'),
            hintText: t('hh.name_hint'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: Text(t('hh.create_btn')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _run(() {
      final repo = HouseholdRepository(ref.read(apiClientProvider));
      return repo.createHousehold(name);
    });
  }

  Future<void> _join() async {
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t('hh.join')),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: t('hh.code_label_only'),
            hintText: t('hh.invite_hint'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(codeCtrl.text.trim()),
            child: Text(t('hh.join_btn')),
          ),
        ],
      ),
    );
    if (code == null || code.length != 8) return;
    await _run(() {
      final repo = HouseholdRepository(ref.read(apiClientProvider));
      return repo.joinHousehold(code);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(authProvider.notifier).finishVaultSetup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(apiClientProvider).handleError(e).toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 110),
                const SizedBox(height: 24),
                Text(
                  t('hh.setup_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t('hh.setup_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                _ActionCard(
                  icon: AppIcons.home,
                  title: t('hh.create_new'),
                  subtitle: t('hh.setup_create_desc'),
                  buttonLabel: t('hh.create_btn'),
                  onTap: _busy ? null : _create,
                ),
                const SizedBox(height: 14),
                _ActionCard(
                  icon: AppIcons.users,
                  title: t('hh.join'),
                  subtitle: t('hh.setup_join_desc'),
                  buttonLabel: t('hh.join_btn'),
                  onTap: _busy ? null : _join,
                ),
                const SizedBox(height: 24),
                if (_busy)
                  const CircularProgressIndicator(strokeWidth: 2)
                else
                  Text(
                    t('hh.setup_note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(icon, size: 22, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
              ),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}