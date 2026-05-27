import 'package:intl/intl.dart';

String formatCurrency(int amount) {
  final formatter = NumberFormat('#,###', 'id_ID');
  return 'Rp${formatter.format(amount)}';
}

String formatCurrencyCompact(int amount) {
  if (amount >= 1000000) {
    final juta = amount / 1000000;
    return 'Rp${juta.toStringAsFixed(juta == juta.roundToDouble() ? 0 : 1)}jt';
  }
  if (amount >= 1000) {
    final ribu = amount / 1000;
    return 'Rp${ribu.toStringAsFixed(0)}rb';
  }
  return 'Rp$amount';
}
