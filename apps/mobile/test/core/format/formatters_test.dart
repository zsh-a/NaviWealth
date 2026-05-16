import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';

Decimal _d(String v) => Decimal.parse(v);

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  group('AppFormatters (zh-CN)', () {
    final f = AppFormatters(locale: const Locale('zh', 'CN'));

    test('currency uses CNY symbol and thousands separators', () {
      final result = f.currency(_d('12345.67'));
      expect(result.contains('¥'), isTrue);
      expect(result.contains('12,345.67'), isTrue);
    });

    test('compactCurrency uses Chinese 万 grouping for large amounts', () {
      final result = f.compactCurrency(_d('15000'));
      expect(result.contains('万'), isTrue);
    });

    test('percent renders ratio as percentage with default 2 decimals', () {
      expect(f.percent(0.1234), '12.34%');
    });

    test('signedPercent prefixes + for gains and - for losses', () {
      expect(f.signedPercent(0.05).startsWith('+'), isTrue);
      expect(f.signedPercent(-0.05).startsWith('-'), isTrue);
      expect(f.signedPercent(0), '0.00%');
    });

    test('date / longDate format in zh conventions', () {
      final d = DateTime(2026, 4, 28);
      expect(f.date(d), '2026/4/28');
      expect(f.longDate(d), contains('2026'));
      expect(f.longDate(d), contains('4'));
      expect(f.longDate(d), contains('28'));
    });
  });

  group('AppFormatters (en-US)', () {
    final f = AppFormatters(locale: const Locale('en', 'US'));

    test('currency formats USD with dollar sign', () {
      expect(f.currency(_d('1000'), code: 'USD'), contains(r'$'));
    });

    test('date follows en-US M/d/y order', () {
      final result = f.date(DateTime(2026, 4, 28));
      expect(result, '4/28/2026');
    });

    test('compactCurrency uses K/M for large amounts', () {
      final result = f.compactCurrency(_d('12000'), code: 'USD');
      expect(result, contains('K'));
    });
  });

  test('currency overrides decimalDigits when supplied', () {
    final f = AppFormatters(locale: const Locale('en', 'US'));
    final result = f.currency(_d('1.5'), code: 'USD', decimalDigits: 4);
    expect(result, contains('1.5000'));
  });

  test('currency without symbol returns plain numeric string', () {
    final f = AppFormatters(locale: const Locale('en', 'US'));
    final result = f.currency(_d('1234.5'), code: 'USD', symbol: false);
    expect(result.contains(r'$'), isFalse);
    expect(result, contains('1,234.50'));
  });

  group('signedMoney', () {
    final f = AppFormatters(locale: const Locale('en', 'US'));

    test('formats fiat with sign, symbol and grouped value', () {
      expect(f.signedMoney(_d('1234.5000'), unit: 'USD'), r'+$1,234.5');
    });

    test('formats negative fiat without trailing zeros', () {
      expect(f.signedMoney(_d('-1000.00'), unit: 'CNY'), '-¥1,000');
    });

    test('formats zero without a sign', () {
      expect(f.signedMoney(_d('0.0000'), unit: 'USD'), r'$0');
    });

    test('formats crypto as an asset code', () {
      expect(f.signedMoney(_d('0.1234567800'), unit: 'BTC'), '+0.12345678 BTC');
    });

    test('formats security units with display symbol', () {
      expect(f.signedMoney(_d('10.0000'), unit: 'us_stock:AAPL'), '+10 AAPL');
    });

    test('can suppress positive sign for balances', () {
      expect(
        f.signedMoney(_d('2500.00'), unit: 'USD', showPositiveSign: false),
        r'$2,500',
      );
    });
  });
}
