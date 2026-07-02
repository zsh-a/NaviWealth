import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/decimal_precision.dart';

void main() {
  group('DecimalPrecisionRules.maxQuantityScale', () {
    test('crypto allows up to 18 fractional digits', () {
      expect(DecimalPrecisionRules.maxQuantityScale(AssetType.crypto), 18);
    });

    test('stocks / ETFs cap at 8', () {
      expect(DecimalPrecisionRules.maxQuantityScale(AssetType.stock), 8);
      expect(DecimalPrecisionRules.maxQuantityScale(AssetType.etf), 8);
    });

    test('cash caps at 4', () {
      expect(DecimalPrecisionRules.maxQuantityScale(AssetType.cash), 4);
    });
  });

  group('DecimalPrecisionRules.fractionalDigits', () {
    test('integer reports zero fractional digits', () {
      expect(DecimalPrecisionRules.fractionalDigits(Decimal.parse('100')), 0);
    });

    test('strips trailing zeros so 1.10 == 1.1 == 1 fractional digit', () {
      expect(DecimalPrecisionRules.fractionalDigits(Decimal.parse('1.10')), 1);
      expect(DecimalPrecisionRules.fractionalDigits(Decimal.parse('1.1')), 1);
    });

    test('counts every significant digit otherwise', () {
      expect(
        DecimalPrecisionRules.fractionalDigits(
          Decimal.parse('0.000000000000000001'),
        ),
        18,
      );
      expect(
        DecimalPrecisionRules.fractionalDigits(Decimal.parse('1.234567')),
        6,
      );
    });
  });
}
