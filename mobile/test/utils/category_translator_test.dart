import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/shared/utils/category_translator.dart';

void main() {
  group('translateCategory', () {
    test('returns input for expense category', () {
      expect(translateCategory('Makanan & Minuman'), 'Makanan & Minuman');
    });

    test('returns input for transport category', () {
      expect(translateCategory('Transportasi & Bensin'), 'Transportasi & Bensin');
    });

    test('returns input for baby category', () {
      expect(translateCategory('Kebutuhan Bayi/Anak'), 'Kebutuhan Bayi/Anak');
    });

    test('returns input for income category', () {
      expect(translateCategory('Gaji'), 'Gaji');
    });

    test('returns input for freelance', () {
      expect(translateCategory('Freelance'), 'Freelance');
    });

    test('returns input for daily shopping', () {
      expect(translateCategory('Belanja Harian'), 'Belanja Harian');
    });

    test('returns input for entertainment', () {
      expect(translateCategory('Hiburan'), 'Hiburan');
    });

    test('returns input for bills category', () {
      expect(translateCategory('Tagihan & Cicilan'), 'Tagihan & Cicilan');
    });

    test('returns input for health category', () {
      expect(translateCategory('Kesehatan'), 'Kesehatan');
    });

    test('returns input for education category', () {
      expect(translateCategory('Pendidikan'), 'Pendidikan');
    });

    test('returns input for savings category', () {
      expect(translateCategory('Tabungan & Investasi'), 'Tabungan & Investasi');
    });

    test('returns input for investment', () {
      expect(translateCategory('Investasi'), 'Investasi');
    });

    test('returns input for bonus', () {
      expect(translateCategory('Bonus & THR'), 'Bonus & THR');
    });

    test('returns input for lainnya expense', () {
      expect(translateCategory('Lainnya'), 'Lainnya');
    });

    test('returns input for lainnya income', () {
      expect(translateCategory('Lainnya'), 'Lainnya');
    });

    test('returns input for transfer category', () {
      expect(translateCategory('Transfer'), 'Transfer');
    });

    test('returns input for household needs', () {
      expect(translateCategory('Kebutuhan Rumah Tangga'), 'Kebutuhan Rumah Tangga');
    });

    test('returns input for household income', () {
      expect(translateCategory('Penghasilan Rumah Tangga'), 'Penghasilan Rumah Tangga');
    });

    test('returns original for unknown category', () {
      expect(translateCategory('Asuransi'), 'Asuransi');
    });

    test('returns empty for empty string', () {
      expect(translateCategory(''), '');
    });

    test('is identity function', () {
      expect(translateCategory('makanan & minuman'), 'makanan & minuman');
    });
  });
}
