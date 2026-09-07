import 'package:flutter/material.dart';

/// Login/register mascot: chicken on a rounded plate that matches theme.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        dark ? 'assets/logo_login_dark.jpg' : 'assets/logo_login_light.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
