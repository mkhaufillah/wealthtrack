import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/copy_fallback.dart';

String friendlyErrorText(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return t('err.generic');
  final low = s.toLowerCase();
  if (low.contains('<html') ||
      low.contains('<!doctype') ||
      low.contains('<body') ||
      low.contains('<head')) {
    return t('err.generic');
  }
  if (s.length > 280) return t('err.generic');
  return s;
}

class ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorDisplay({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final text = friendlyErrorText(message);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 96),
            const SizedBox(height: 20),
            Text(
              t('err.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry ?? () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: Text(t('err.refresh')),
            ),
          ],
        ),
      ),
    );
  }
}
