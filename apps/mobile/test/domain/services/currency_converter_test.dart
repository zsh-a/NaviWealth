import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';

FxRate rate({
  String base = 'USD',
  String quote = 'CNY',
  required DateTime date,
  required String rate,
  String source = 'test',
}) {
  return FxRate(
    base: base,
    quote: quote,
    date: date,
    rate: Decimal.parse(rate),
    source: source,
  );
}

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  group('FxRateCurrencyConverter', () {
    test('same-currency conversion returns identical Money', () {
      final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(const []));
      final m = Money.fromInt(100, 'USD');
      expect(converter.convert(m, 'USD'), m);
    });

    test('uses direct rate when registered', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([rate(date: day(2026, 4, 28), rate: '7.2')]),
      );
      expect(
        converter.convert(Money.fromInt(10, 'USD'), 'CNY'),
        Money.parse('72.0', 'CNY'),
      );
    });

    test('falls back to inverse rate when only reverse is registered', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          // 1 USD = 7.2 CNY, recorded as USD→CNY
          rate(base: 'USD', quote: 'CNY', date: day(2026, 4, 28), rate: '8'),
        ]),
      );
      // Convert CNY → USD using inverse 1/8 = 0.125
      expect(
        converter.convert(Money.fromInt(80, 'CNY'), 'USD'),
        Money.parse('10.000', 'USD'),
      );
    });

    test('without `on`, uses the most recent rate', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          rate(date: day(2026, 1, 1), rate: '7.0'),
          rate(date: day(2026, 4, 28), rate: '7.2'),
          rate(date: day(2026, 3, 1), rate: '7.1'),
        ]),
      );
      expect(
        converter.convert(Money.fromInt(100, 'USD'), 'CNY'),
        Money.parse('720.0', 'CNY'),
      );
    });

    test('with `on`, uses the rate from that exact date when available', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          rate(date: day(2026, 1, 1), rate: '7.0'),
          rate(date: day(2026, 4, 28), rate: '7.2'),
        ]),
      );
      expect(
        converter.convert(
          Money.fromInt(100, 'USD'),
          'CNY',
          on: day(2026, 1, 1),
        ),
        Money.parse('700.0', 'CNY'),
      );
    });

    test('backfills to nearest earlier rate on a calendar holiday gap', () {
      // FX markets closed 2026-01-01 (New Year). Last quote was 2025-12-31.
      // Asking for 2026-01-01 should return the 2025-12-31 rate, not throw.
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          rate(date: day(2025, 12, 31), rate: '7.0'),
          rate(date: day(2026, 1, 5), rate: '7.1'),
        ]),
      );
      expect(
        converter.convert(
          Money.fromInt(100, 'USD'),
          'CNY',
          on: day(2026, 1, 1),
        ),
        Money.parse('700.0', 'CNY'),
      );
    });

    test('throws when no rate exists on or before the requested date', () {
      // Asking for a date BEFORE we have any data — backfill cannot help.
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([rate(date: day(2026, 4, 28), rate: '7.2')]),
      );
      expect(
        () => converter.convert(
          Money.fromInt(100, 'USD'),
          'CNY',
          on: day(2026, 1, 1),
        ),
        throwsA(isA<FxRateNotFoundError>()),
      );
    });

    test('throws when the pair is entirely unknown', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([rate(date: day(2026, 4, 28), rate: '7.2')]),
      );
      expect(
        () => converter.convert(Money.fromInt(100, 'JPY'), 'USD'),
        throwsA(isA<FxRateNotFoundError>()),
      );
    });

    test('case-insensitive currency codes on input', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([
          rate(base: 'usd', quote: 'cny', date: day(2026, 4, 28), rate: '7.2'),
        ]),
      );
      expect(
        converter.convert(Money.fromInt(10, 'usd'), 'cny'),
        Money.parse('72.0', 'CNY'),
      );
    });

    test('accepts intra-day timestamp for `on` and floors to the day', () {
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup([rate(date: day(2026, 4, 28), rate: '7.2')]),
      );
      expect(
        converter.convert(
          Money.fromInt(10, 'USD'),
          'CNY',
          on: DateTime.utc(2026, 4, 28, 23, 59, 59),
        ),
        Money.parse('72.0', 'CNY'),
      );
    });

    test(
      'prefers most recent observation when forward and inverse conflict',
      () {
        // Forward USD→CNY @ 2026-01-01 = 7.0
        // Inverse CNY→USD @ 2026-04-01 = 0.10  (i.e. 1 USD = 10 CNY)
        // The inverse is more recent, so it wins for a no-`on` query.
        final converter = FxRateCurrencyConverter(
          InMemoryFxRateLookup([
            rate(date: day(2026, 1, 1), rate: '7.0'),
            rate(base: 'CNY', quote: 'USD', date: day(2026, 4, 1), rate: '0.1'),
          ]),
        );
        expect(
          converter.convert(Money.fromInt(1, 'USD'), 'CNY'),
          Money.parse('10.0', 'CNY'),
        );
      },
    );
  });

  group('InMemoryFxRateLookup', () {
    test('rateFor with no rates returns null', () {
      final lookup = InMemoryFxRateLookup(const []);
      expect(lookup.rateFor('USD', 'CNY'), isNull);
      expect(lookup.rateFor('USD', 'CNY', on: day(2026, 1, 1)), isNull);
    });

    test('rateFor rejects base == quote', () {
      final lookup = InMemoryFxRateLookup(const []);
      expect(() => lookup.rateFor('USD', 'usd'), throwsArgumentError);
    });

    test('preserves source on the returned rate', () {
      final lookup = InMemoryFxRateLookup([
        rate(date: day(2026, 4, 28), rate: '7.2', source: 'ecb'),
      ]);
      expect(lookup.rateFor('USD', 'CNY')!.source, 'ecb');
    });
  });
}
