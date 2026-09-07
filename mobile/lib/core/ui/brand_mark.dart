import 'package:flutter/material.dart';

/// Login/register mascot: chicken on a rounded plate that matches theme.
class BrandMark extends StatelessWidget {
  final double size;
  final bool animate;
  const BrandMark({super.key, this.size = 96, this.animate = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(size * 0.22);
    final image = ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        dark ? 'assets/logo_login_dark.jpg' : 'assets/logo_login_light.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
    if (!animate) {
      return SizedBox(width: size, height: size, child: image);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      child: image,
    );
  }
}
