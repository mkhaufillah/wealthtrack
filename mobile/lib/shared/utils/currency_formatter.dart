import 'package:intl/intl.dart';
import '../../core/ui/copy_fallback.dart';
import '../../core/ui/money.dart';

String formatCurrency(int amount) {
  final formatter = NumberFormat('#,###', 'id_ID');
  var body = formatter.format(amount.abs());
  if (MoneyFormat.groupSep != '.') {
    body = body.replaceAll('.', MoneyFormat.groupSep);
  }
  final sign = amount < 0 ? '-' : '';
  return '$sign${MoneyFormat.prefix}$body';
}

String _trimNum(double n) {
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  if (n >= 100) return n.toStringAsFixed(0);
  if (n >= 10) return n.toStringAsFixed(1);
  return n.toStringAsFixed(1);
}

/// Formats raw digits as a live currency input preview, following the active
/// `ui_config` prefix + group separator. "50000" -> "Rp 50.000".
String formatIdrInput(String text) {
  final digits = text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  final sep = MoneyFormat.groupSep;
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write(sep);
    buf.write(digits[i]);
    count++;
  }
  return '${MoneyFormat.prefix} ${buf.toString().split('').reversed.join('')}';
}

/// Compact ID labels so hundreds of millions / billions still fit a card.
/// 1.200.000 → Rp1,2jt · 329.359.941 → Rp329jt · 1.500.000.000 → Rp1,5M
String formatCurrencyCompact(int amount) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (abs >= 1000000000) {
    return '${sign}${MoneyFormat.prefix}${_trimNum(abs / 1000000000)}${t('money.billion')}';
  }
  if (abs >= 1000000) {
    return '${sign}${MoneyFormat.prefix}${_trimNum(abs / 1000000)}${t('money.million')}';
  }
  if (abs >= 10000) {
    return '${sign}${MoneyFormat.prefix}${_trimNum(abs / 1000)}${t('money.thousand')}';
  }
  return formatCurrency(amount);
}
