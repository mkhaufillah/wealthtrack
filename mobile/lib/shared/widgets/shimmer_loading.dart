import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// A shimmer placeholder that mimics a card layout during loading.
/// Automatically matches light/dark mode.
class ShimmerCard extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const ShimmerCard({
    super.key,
    this.height = 100,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = AppColors.surface;
    final highlightColor = isDark ? AppColors.darkCard : AppColors.divider;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: padding ?? const EdgeInsets.all(16),
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// Shimmer loading screen with multiple card placeholders.
/// Use as a drop-in replacement for LoadingIndicator.
class ShimmerLoading extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ShimmerLoading({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 100,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (_, __) => ShimmerCard(height: itemHeight),
    );
  }
}
