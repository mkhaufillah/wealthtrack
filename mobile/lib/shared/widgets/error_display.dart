import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/app_icons.dart';
import '../../core/ui/copy_fallback.dart';

class ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorDisplay({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.alert, size: 48, color: AppColors.highlight),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: AppIcon(AppIcons.refresh, size: 18),
                label: Text(t('common.retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
