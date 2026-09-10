import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/ui_config.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _slides = [
    _Slide(
      image: 'assets/onboarding/lang.jpg',
      titleKey: 'onboarding.choose',
      subKey: 'onboarding.hint',
      lang: true,
    ),
    _Slide(
      image: 'assets/onboarding/money.jpg',
      titleKey: 'onboarding.p1_title',
      subKey: 'onboarding.p1_sub',
    ),
    _Slide(
      image: 'assets/onboarding/bank.jpg',
      titleKey: 'onboarding.p2_title',
      subKey: 'onboarding.p2_sub',
    ),
    _Slide(
      image: 'assets/onboarding/money.jpg',
      titleKey: 'onboarding.p3_title',
      subKey: 'onboarding.p3_sub',
      lock: true,
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index < _slides.length - 1) {
      await _page.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await ref.read(onboardingProvider.notifier).complete();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    ref.watch(uiConfigProvider);
    final last = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (ctx, i) {
                  final s = _slides[i];
                  final imgH = s.lock
                      ? (MediaQuery.sizeOf(ctx).height * 0.22).clamp(100.0, 160.0)
                      : (MediaQuery.sizeOf(ctx).height * 0.32).clamp(140.0, 240.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Column(
                      children: [
                        SizedBox(
                          height: imgH,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              s.image,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          t(s.titleKey),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (s.lang) ...[
                          const SizedBox(height: 4),
                          Text(
                            t('onboarding.choose_en'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (s.lock) ...[
                          Text(
                            t(s.subKey),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _LockPoint(
                            icon: AppIcons.shield,
                            text: t('onboarding.p3_a'),
                          ),
                          const SizedBox(height: 8),
                          _LockPoint(
                            icon: AppIcons.user,
                            text: t('onboarding.p3_b'),
                          ),
                          const SizedBox(height: 8),
                          _LockPoint(
                            icon: AppIcons.alert,
                            text: t('onboarding.p3_c'),
                          ),
                        ] else
                          Text(
                            t(s.subKey),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        if (s.lang) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _LangCard(
                                  label: t('profile.lang_id'),
                                  selected: locale != 'en-US',
                                  onTap: () => ref
                                      .read(localeProvider.notifier)
                                      .setLocale('id-ID'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LangCard(
                                  label: t('profile.lang_en'),
                                  selected: locale == 'en-US',
                                  onTap: () => ref
                                      .read(localeProvider.notifier)
                                      .setLocale('en-US'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        Container(
                          width: i == _index ? 18 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.accent
                                : AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('onboarding-next'),
                      onPressed: _next,
                      child: Text(last ? t('onboarding.start') : t('onboarding.next')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String image;
  final String titleKey;
  final String subKey;
  final bool lang;
  final bool lock;
  const _Slide({
    required this.image,
    required this.titleKey,
    required this.subKey,
    this.lang = false,
    this.lock = false,
  });
}

class _LockPoint extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String text;
  const _LockPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.mint.withOpacity(0.28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppIcon(icon, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withOpacity(0.18) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
