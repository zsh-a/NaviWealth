import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';

void main() {
  FxRate make({
    String base = 'USD',
    String quote = 'CNY',
    DateTime? date,
    String rate = '7.2',
    String source = 'manual',
  }) {
    return FxRate(
      base: base,
      quote: quote,
      date: date ?? DateTime.utc(2026, 4, 28),
      rate: Decimal.parse(rate),
      source: source,
    );
  }

  group('FxRate', () {
    test('normalizes currencies to uppercase', () {
      final r = make(base: 'usd', quote: 'cny');
      expect(r.base, 'USD');
      expect(r.quote, 'CNY');
    });

    test('truncates date to UTC calendar day', () {
      final r = make(date: DateTime.utc(2026, 4, 28, 23, 59, 59));
      expect(r.date, DateTime.utc(2026, 4, 28));
    });

    test('rejects non-positive rate', () {
      expect(
        () => FxRate(
          base: 'USD',
          quote: 'CNY',
          date: DateTime.utc(2026, 1, 1),
          rate: Decimal.zero,
          source: 'manual',
        ),
        throwsArgumentError,
      );
    });

    test('rejects identical base and quote', () {
      expect(() => make(base: 'USD', quote: 'USD'), throwsArgumentError);
    });

    test('inverse swaps direction and reciprocates rate', () {
      final inv = make(rate: '8').inverse();
      expect(inv.base, 'CNY');
      expect(inv.quote, 'USD');
      expect(inv.rate, Decimal.parse('0.125'));
      expect(inv.source, 'manual');
    });

    test('equality covers all fields including source', () {
      expect(make(), equals(make()));
      expect(make(source: 'ecb'), isNot(equals(make(source: 'manual'))));
    });
  });
}
