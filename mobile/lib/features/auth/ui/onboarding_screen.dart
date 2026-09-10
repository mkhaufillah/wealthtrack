import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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
      hintKey: 'onboarding.p3_hint',
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
                  final imgH = (MediaQuery.sizeOf(ctx).height * 0.32).clamp(140.0, 240.0);
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
                        if (s.hintKey != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            t(s.hintKey!),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
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
  final String? hintKey;
  final bool lang;
  const _Slide({
    required this.image,
    required this.titleKey,
    required this.subKey,
    this.hintKey,
    this.lang = false,
  });
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
