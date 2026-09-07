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
    final baseColor = AppColors.surface;
    final highlightColor = AppColors.divider;

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

/// Homepage loading — mirrors HiRow, hero, pockets, shortcuts, recent.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.divider,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(height: 22, width: 148, radius: 8),
                    const SizedBox(height: 8),
                    _Bone(height: 12, width: 200, radius: 6),
                  ],
                ),
              ),
              const _Bone(height: 44, width: 44, radius: 16),
            ],
          ),
          const SizedBox(height: 14),
          const _Bone(height: 148, radius: 28),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: _Bone(height: 110, radius: 22)),
              SizedBox(width: 10),
              Expanded(child: _Bone(height: 110, radius: 22)),
            ],
          ),
          const SizedBox(height: 10),
          const _Bone(height: 112, radius: 22),
          const SizedBox(height: 22),
          const _Bone(height: 16, width: 96, radius: 8),
          const SizedBox(height: 8),
          const _Bone(height: 168, radius: 22),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const _Bone({required this.height, this.width, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
