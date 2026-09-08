import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/ui/money.dart';
import 'package:wealthtrack/shared/utils/currency_formatter.dart';

void main() {
  tearDown(() {
    // reset global format state between groups
    MoneyFormat.apply({
      'currency_prefix': 'Rp',
      'group_sep': '.',
      'decimal_sep': ',',
    });
  });

  group('MoneyFormat.apply', () {
    test('applies server-driven format fields', () {
      MoneyFormat.apply({
        'currency_prefix': 'USD',
        'group_sep': ',',
        'decimal_sep': '.',
      });
      expect(MoneyFormat.prefix, 'USD');
      expect(MoneyFormat.groupSep, ',');
      expect(MoneyFormat.decimalSep, '.');
    });

    test('missing fields fall back to current values', () {
      MoneyFormat.prefix = 'X';
      MoneyFormat.apply({'currency_prefix': 'Rp'});
      expect(MoneyFormat.prefix, 'Rp');
      expect(MoneyFormat.groupSep, '.'); // unchanged
    });
  });

  group('formatCurrency', () {
    test('formats thousand', () {
      expect(formatCurrency(1000), 'Rp1.000');
    });
    test('formats million', () {
      expect(formatCurrency(1500000), 'Rp1.500.000');
    });
    test('formats zero', () {
      expect(formatCurrency(0), 'Rp0');
    });
    test('formats small number', () {
      expect(formatCurrency(500), 'Rp500');
    });
    test('negative sign precedes prefix', () {
      expect(formatCurrency(-2500), '-Rp2.500');
    });
    test('honors custom group separator from ui_config', () {
      MoneyFormat.apply({'group_sep': ','});
      expect(formatCurrency(1000000), 'Rp1,000,000');
    });
  });

  group('formatIdrInput', () {
    test('groups raw digits for live input preview', () {
      expect(formatIdrInput('50000'), 'Rp 50.000');
    });
    test('strips non-digit characters', () {
      expect(formatIdrInput('Rp 1,200,000'), 'Rp 1.200.000');
    });
    test('empty input yields empty string', () {
      expect(formatIdrInput(''), '');
    });
    test('non-numeric input yields empty string', () {
      expect(formatIdrInput('abc .'), '');
    });
    test('short amount no grouping', () {
      expect(formatIdrInput('999'), 'Rp 999');
    });
    test('four digits groups once', () {
      expect(formatIdrInput('1000'), 'Rp 1.000');
    });
    test('six digits groups twice', () {
      expect(formatIdrInput('1000000'), 'Rp 1.000.000');
    });
    test('honors custom prefix and separator', () {
      MoneyFormat.apply({'currency_prefix': 'US\$', 'group_sep': ','});
      expect(formatIdrInput('1234567'), 'US\$ 1,234,567');
    });
  });

  group('formatCurrencyCompact', () {
    test('billion shows M', () {
      expect(formatCurrencyCompact(1500000000), 'Rp1.5M');
    });
    test('million shows jt', () {
      expect(formatCurrencyCompact(1200000), 'Rp1.2jt');
    });
    test('hundreds of millions round to whole jt', () {
      expect(formatCurrencyCompact(329359941), 'Rp329jt');
    });
    test('thousands show rb', () {
      expect(formatCurrencyCompact(25000), 'Rp25rb');
    });
    test('small returns exact formatted', () {
      expect(formatCurrencyCompact(500), 'Rp500');
    });
    test('negative sign preserved', () {
      expect(formatCurrencyCompact(-1200000), '-Rp1.2jt');
    });
    test('12j500 barrier uses rb', () {
      expect(formatCurrencyCompact(12500), 'Rp12.5rb');
    });
  });
}