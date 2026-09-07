import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/copy_fallback.dart';

class DebtHomeScreen extends StatelessWidget {
  const DebtHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Row(
              children: [
                IconButton(
                  icon: AppIcon(AppIcons.back),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: 4),
                Text(
                  t('debt.title'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Pilih yang mau diurus. Gak usah tegang — ini catetan, bukan bank.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _DebtHero(
              icon: AppIcons.house,
              wash: AppColors.mint,
              title: t('debt.kpr'),
              subtitle: t('debt.kpr_sub'),
              onTap: () => context.push('/debt/kpr'),
            ),
            const SizedBox(height: 12),
            _DebtHero(
              icon: AppIcons.card,
              wash: AppColors.butter,
              title: t('debt.cc'),
              subtitle: t('debt.cc_sub'),
              onTap: () => context.push('/debt/credit-cards'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtHero extends StatelessWidget {
  final List<List<dynamic>> icon;
  final Color wash;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _DebtHero({
    required this.icon,
    required this.wash,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: wash,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(child: AppIcon(icon, size: 64, color: AppColors.onAccent)),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
