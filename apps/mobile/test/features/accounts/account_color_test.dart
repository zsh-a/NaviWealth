import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/shared/account_color.dart';

void main() {
  group('parseAccountColor', () {
    test('parses six-digit account colors as opaque', () {
      expect(parseAccountColor('#112233')?.toARGB32(), 0xFF112233);
      expect(parseAccountColor('445566')?.toARGB32(), 0xFF445566);
    });

    test('preserves explicit alpha values', () {
      expect(parseAccountColor('#80112233')?.toARGB32(), 0x80112233);
      expect(parseAccountColor('40445566')?.toARGB32(), 0x40445566);
    });

    test('rejects empty or malformed values', () {
      expect(parseAccountColor(null), isNull);
      expect(parseAccountColor(''), isNull);
      expect(parseAccountColor('#12345'), isNull);
      expect(parseAccountColor('not-a-color'), isNull);
    });
  });
}
