import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/utils/category_translator.dart';

void main() {
  group('translateCategory', () {
    test('translates expense category', () {
      expect(translateCategory('Makanan & Minuman'), 'Food & Drinks');
    });

    test('translates transport category', () {
      expect(translateCategory('Transportasi & Bensin'), 'Transport & Fuel');
    });

    test('translates baby category', () {
      expect(translateCategory('Kebutuhan Bayi/Anak'), 'Baby & Child Needs');
    });

    test('translates income category', () {
      expect(translateCategory('Gaji'), 'Salary');
    });

    test('translates freelance', () {
      expect(translateCategory('Freelance'), 'Freelance');
    });

    test('translates daily shopping', () {
      expect(translateCategory('Belanja Harian'), 'Daily Shopping');
    });

    test('translates entertainment', () {
      expect(translateCategory('Hiburan'), 'Entertainment');
    });

    test('translates bills category', () {
      expect(translateCategory('Tagihan & Cicilan'), 'Bills & Installments');
    });

    test('translates health category', () {
      expect(translateCategory('Kesehatan'), 'Health');
    });

    test('translates education category', () {
      expect(translateCategory('Pendidikan'), 'Education');
    });

    test('translates savings category', () {
      expect(translateCategory('Tabungan & Investasi'), 'Savings & Investment');
    });

    test('translates investment', () {
      expect(translateCategory('Investasi'), 'Investment');
    });

    test('translates bonus', () {
      expect(translateCategory('Bonus & THR'), 'Bonus & THR');
    });

    test('translates lainnya expense', () {
      expect(translateCategory('Lainnya'), 'Other');
    });

    test('translates lainnya income', () {
      // Same Indonesian word for both expense and income
      expect(translateCategory('Lainnya'), 'Other');
    });

    test('returns original for unknown category', () {
      expect(translateCategory('Asuransi'), 'Asuransi');
    });

    test('returns empty for empty string', () {
      expect(translateCategory(''), '');
    });

    test('is case sensitive - exact match required', () {
      // Map keys are exact case, so wrong case falls through
      expect(translateCategory('makanan & minuman'), 'makanan & minuman');
    });
  });
}
