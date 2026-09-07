import 'package:intl/intl.dart';

String formatCurrency(int amount) {
  final formatter = NumberFormat('#,###', 'id_ID');
  return 'Rp${formatter.format(amount)}';
}

String _trimNum(double n) {
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  if (n >= 100) return n.toStringAsFixed(0);
  if (n >= 10) return n.toStringAsFixed(1);
  return n.toStringAsFixed(1);
}

/// Compact ID labels so hundreds of millions / billions still fit a card.
/// 1.200.000 → Rp1,2jt · 329.359.941 → Rp329jt · 1.500.000.000 → Rp1,5M
String formatCurrencyCompact(int amount) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (abs >= 1000000000) {
    return '$signRp${_trimNum(abs / 1000000000)}M';
  }
  if (abs >= 1000000) {
    return '$signRp${_trimNum(abs / 1000000)}jt';
  }
  if (abs >= 10000) {
    return '$signRp${_trimNum(abs / 1000)}rb';
  }
  return formatCurrency(amount);
}
