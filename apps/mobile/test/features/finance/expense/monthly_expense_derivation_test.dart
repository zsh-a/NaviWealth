import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/expense/domain/monthly_expense_derivation.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 4, 1),
  updatedByDevice: 't',
  hlc: Hlc.zero('t'),
);

Expense _expense({
  required String id,
  required Decimal amount,
  required DateTime date,
  String currency = 'CNY',
}) => Expense(
  id: id,
  categoryId: 'cat-1',
  amount: amount,
  currency: currency,
  tradeDate: date,
  sync: _meta(),
);

CurrencyConverter _converterWithRates(Iterable<FxRate> rates) =>
    FxRateCurrencyConverter(InMemoryFxRateLookup(rates));

void main() {
  group('MonthlyExpenseDerivation', () {
    test('averages the last 3 complete months ending before asOf', () {
      final derivation = MonthlyExpenseDerivation(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final expenses = [
        _expense(
          id: 'jan',
          amount: Decimal.parse('300'),
          date: DateTime.utc(2026, 1, 5),
        ),
        _expense(
          id: 'feb',
          amount: Decimal.parse('600'),
          date: DateTime.utc(2026, 2, 10),
        ),
        _expense(
          id: 'mar',
          amount: Decimal.parse('900'),
          date: DateTime.utc(2026, 3, 15),
        ),
      ];
      final avg = derivation.compute(
        expenses: expenses,
        windowMonths: 3,
        asOf: DateTime.utc(2026, 4, 17),
      );
      // (300 + 600 + 900) / 3 = 600
      expect(avg.average.amount, Decimal.parse('600'));
      expect(avg.windowMonths, 3);
      expect(avg.windowStart, DateTime.utc(2026, 1, 1));
      expect(avg.windowEnd, DateTime.utc(2026, 4, 1));
    });

    test(
      'excludes the in-progress month (current-month spend not counted)',
      () {
        final derivation = MonthlyExpenseDerivation(
          converter: _converterWithRates(const []),
          baseCurrency: 'CNY',
        );
        final expenses = [
          _expense(
            id: 'apr-so-far',
            amount: Decimal.parse('2000'),
            date: DateTime.utc(2026, 4, 5),
          ),
          _expense(
            id: 'mar',
            amount: Decimal.parse('900'),
            date: DateTime.utc(2026, 3, 15),
          ),
        ];
        final avg = derivation.compute(
          expenses: expenses,
          windowMonths: 1,
          asOf: DateTime.utc(2026, 4, 10),
        );
        // April should be excluded; only March (900) counts.
        expect(avg.average.amount, Decimal.parse('900'));
      },
    );

    test('returns zero when no expenses fall in the window', () {
      final derivation = MonthlyExpenseDerivation(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final avg = derivation.compute(
        expenses: const [],
        windowMonths: 3,
        asOf: DateTime.utc(2026, 4, 17),
      );
      expect(avg.average.amount, Decimal.zero);
      expect(avg.average.currency, 'CNY');
    });

    test('skips expenses lacking an FX rate and counts them', () {
      final derivation = MonthlyExpenseDerivation(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final expenses = [
        _expense(
          id: 'jan-eur',
          amount: Decimal.parse('100'),
          date: DateTime.utc(2026, 1, 5),
          currency: 'EUR',
        ),
        _expense(
          id: 'feb-cny',
          amount: Decimal.parse('300'),
          date: DateTime.utc(2026, 2, 10),
        ),
      ];
      final avg = derivation.compute(
        expenses: expenses,
        windowMonths: 3,
        asOf: DateTime.utc(2026, 4, 17),
      );
      // Only feb counts: 300 / 3 = 100.
      expect(avg.average.amount, Decimal.parse('100'));
      expect(avg.skippedFxCount, 1);
    });

    test('rejects non-positive windowMonths', () {
      final derivation = MonthlyExpenseDerivation(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      expect(
        () => derivation.compute(expenses: const [], windowMonths: 0),
        throwsArgumentError,
      );
      expect(
        () => derivation.compute(expenses: const [], windowMonths: -3),
        throwsArgumentError,
      );
    });

    test(
      'window wraps year boundary (Apr asOf, 6-month window → Oct..Mar)',
      () {
        final derivation = MonthlyExpenseDerivation(
          converter: _converterWithRates(const []),
          baseCurrency: 'CNY',
        );
        final expenses = [
          // Outside window — Sep 2025.
          _expense(
            id: 'sep',
            amount: Decimal.parse('999'),
            date: DateTime.utc(2025, 9, 30),
          ),
          // Inside window.
          _expense(
            id: 'oct',
            amount: Decimal.parse('100'),
            date: DateTime.utc(2025, 10, 1),
          ),
          _expense(
            id: 'mar',
            amount: Decimal.parse('200'),
            date: DateTime.utc(2026, 3, 31),
          ),
        ];
        final avg = derivation.compute(
          expenses: expenses,
          windowMonths: 6,
          asOf: DateTime.utc(2026, 4, 17),
        );
        // (100 + 200) / 6 = 50
        expect(avg.average.amount, Decimal.parse('50'));
        expect(avg.windowStart, DateTime.utc(2025, 10, 1));
        expect(avg.windowEnd, DateTime.utc(2026, 4, 1));
      },
    );
  });
}
