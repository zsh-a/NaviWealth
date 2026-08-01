import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/domain/minor_unit_amount.dart';

void main() {
  test('formats minor units exactly without floating point conversion', () {
    expect(formatMinorUnitAmount(0), '0.00');
    expect(formatMinorUnitAmount(5), '0.05');
    expect(formatMinorUnitAmount(150), '1.50');
    expect(formatMinorUnitAmount(-12345), '-123.45');
    expect(formatMinorUnitAmount(9007199254740993), '90071992547409.93');
  });

  test('parses supported unsigned decimal forms exactly', () {
    expect(parseUnsignedMinorUnitAmount('0'), 0);
    expect(parseUnsignedMinorUnitAmount('1'), 100);
    expect(parseUnsignedMinorUnitAmount('1.'), 100);
    expect(parseUnsignedMinorUnitAmount('1.5'), 150);
    expect(parseUnsignedMinorUnitAmount('.05'), 5);
    expect(parseUnsignedMinorUnitAmount(' 123.45 '), 12345);
    expect(parseUnsignedMinorUnitAmount('90071992547409.93'), 9007199254740993);
  });

  test('rejects rounding, signs, and malformed values', () {
    for (final value in <String>[
      '',
      '.',
      '-1',
      '+1',
      '1.234',
      '1,000',
      'NaN',
      'Infinity',
    ]) {
      expect(
        parseUnsignedMinorUnitAmount(value),
        isNull,
        reason: 'expected "$value" to be rejected',
      );
    }
  });
}
