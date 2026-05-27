import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/utils/currency_formatter.dart';
import 'package:wealthtrack/shared/utils/date_formatter.dart';

void main() {
  group('formatCurrency', () {
    test('formats thousand', () => expect(formatCurrency(1000), 'Rp1.000'));
    test('formats million', () => expect(formatCurrency(1500000), 'Rp1.500.000'));
    test('formats zero', () => expect(formatCurrency(0), 'Rp0'));
    test('formats small number', () => expect(formatCurrency(500), 'Rp500'));
    test('formats large number', () => expect(formatCurrency(100000000), 'Rp100.000.000'));
  });

  group('formatCurrencyCompact', () {
    test('shows juta for millions', () => expect(formatCurrencyCompact(1500000), 'Rp1,5jt'));
    test('shows rb for thousands', () => expect(formatCurrencyCompact(25000), 'Rp25rb'));
    test('shows exact for small', () => expect(formatCurrencyCompact(500), 'Rp500'));
    test('rounds juta for exact million', () => expect(formatCurrencyCompact(2000000), 'Rp2jt'));
    test('handles zero', () => expect(formatCurrencyCompact(0), 'Rp0'));
    test('handles hundred', () => expect(formatCurrencyCompact(100), 'Rp100'));
  });

  group('formatDate', () {
    test('formats valid ISO date', () {
      expect(formatDate('2026-05-27'), 'May 27, 2026');
    });
    test('returns original string for invalid date', () {
      expect(formatDate('invalid'), 'invalid');
    });
    test('formats first day of year', () {
      expect(formatDate('2026-01-01'), 'Jan 01, 2026');
    });
  });

  group('formatDateRelative', () {
    test('returns Today for todays date', () {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect(formatDateRelative(today), 'Today');
    });

    test('returns Yesterday for yesterdays date', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      expect(formatDateRelative(yesterday), 'Yesterday');
    });

    test('returns days ago for within a week', () {
      final d = DateTime.now().subtract(const Duration(days: 3)).toIso8601String().substring(0, 10);
      expect(formatDateRelative(d), '3 days ago');
    });

    test('returns month+day for dates older than a week', () {
      final d = DateTime(2026, 1, 15).toIso8601String().substring(0, 10);
      expect(formatDateRelative(d), 'Jan 15');
    });

    test('returns original string for invalid input', () {
      expect(formatDateRelative('not-a-date'), 'not-a-date');
    });
  });
}
