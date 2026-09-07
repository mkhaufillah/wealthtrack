/// Money format from GET /ui/bootstrap. Fallback matches live IDR copy.
class MoneyFormat {
  static String prefix = 'Rp';
  static String groupSep = '.';
  static String decimalSep = ',';

  static void apply(Map<String, dynamic> format) {
    prefix = format['currency_prefix']?.toString() ?? prefix;
    groupSep = format['group_sep']?.toString() ?? groupSep;
    decimalSep = format['decimal_sep']?.toString() ?? decimalSep;
  }
}
