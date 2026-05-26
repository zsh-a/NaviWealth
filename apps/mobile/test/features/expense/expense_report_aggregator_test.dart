import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/expense/domain/expense_report_aggregator.dart';
import 'package:naviwealth/features/expense/domain/expense_report_range.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 4, 1),
  updatedByDevice: 't',
  hlc: Hlc.zero('t'),
);

Expense _expense({
  required String id,
  required String expenseAccountId,
  required Decimal amount,
  required DateTime date,
  String currency = 'CNY',
}) => Expense(
  id: id,
  expenseAccountId: expenseAccountId,
  amount: amount,
  currency: currency,
  tradeDate: date,
  sync: _meta(),
);

CurrencyConverter _converterWithRates(Iterable<FxRate> rates) =>
    FxRateCurrencyConverter(InMemoryFxRateLookup(rates));

void main() {
  group('ExpenseReportAggregator', () {
    test('rolls expenses into categories sorted by total', () {
      final expenses = [
        _expense(
          id: 'e1',
          expenseAccountId: 'food',
          amount: Decimal.parse('120'),
          date: DateTime.utc(2026, 4, 5),
        ),
        _expense(
          id: 'e2',
          expenseAccountId: 'food',
          amount: Decimal.parse('80'),
          date: DateTime.utc(2026, 4, 10),
        ),
        _expense(
          id: 'e3',
          expenseAccountId: 'transport',
          amount: Decimal.parse('50'),
          date: DateTime.utc(2026, 4, 12),
        ),
      ];
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: expenses,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      expect(report.total.amount, Decimal.parse('250'));
      expect(report.byCategory.length, 2);
      expect(report.byCategory.first.expenseAccountId, 'food');
      expect(report.byCategory.first.total.amount, Decimal.parse('200'));
      expect(report.byCategory.first.items.length, 2);
      expect(report.byCategory[1].expenseAccountId, 'transport');
    });

    test('groups expenses by expense account id', () {
      final expenses = [
        _expense(
          id: 'e1',
          expenseAccountId: 'acct-lunch',
          amount: Decimal.parse('30'),
          date: DateTime.utc(2026, 4, 1),
        ),
        _expense(
          id: 'e2',
          expenseAccountId: 'acct-dinner',
          amount: Decimal.parse('70'),
          date: DateTime.utc(2026, 4, 2),
        ),
        _expense(
          id: 'e3',
          expenseAccountId: 'acct-lunch',
          amount: Decimal.parse('15'),
          date: DateTime.utc(2026, 4, 3),
        ),
      ];
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: expenses,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 15),
        ),
      );
      expect(report.byCategory.length, 2);
      // dinner (70) > lunch (45)
      expect(report.byCategory.first.expenseAccountId, 'acct-dinner');
      expect(report.byCategory.first.total.amount, Decimal.parse('70'));
      expect(report.byCategory[1].expenseAccountId, 'acct-lunch');
      expect(report.byCategory[1].total.amount, Decimal.parse('45'));
    });

    test('zero-fills monthly buckets across the range', () {
      final expenses = [
        _expense(
          id: 'e-jan',
          expenseAccountId: 'food',
          amount: Decimal.parse('100'),
          date: DateTime.utc(2026, 2, 5),
        ),
        _expense(
          id: 'e-mar',
          expenseAccountId: 'food',
          amount: Decimal.parse('200'),
          date: DateTime.utc(2026, 4, 10),
        ),
      ];
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: expenses,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.m3,
          now: DateTime.utc(2026, 4, 17),
        ),
      );
      // 3 buckets: Feb / Mar / Apr.
      expect(report.monthlyBuckets.length, 3);
      expect(report.monthlyBuckets[0].key, '2026-02');
      expect(report.monthlyBuckets[0].total.amount, Decimal.parse('100'));
      expect(report.monthlyBuckets[1].key, '2026-03');
      expect(report.monthlyBuckets[1].total.amount, Decimal.zero);
      expect(report.monthlyBuckets[2].key, '2026-04');
      expect(report.monthlyBuckets[2].total.amount, Decimal.parse('200'));
    });

    test('converts foreign-currency expenses to base currency', () {
      final fxDate = DateTime.utc(2026, 4, 10);
      final converter = _converterWithRates([
        FxRate(
          base: 'USD',
          quote: 'CNY',
          date: fxDate,
          rate: Decimal.parse('7.2'),
          source: 'test',
        ),
      ]);
      final expenses = [
        _expense(
          id: 'e1',
          expenseAccountId: 'food',
          amount: Decimal.parse('10'),
          date: DateTime.utc(2026, 4, 12),
          currency: 'USD',
        ),
      ];
      final aggregator = ExpenseReportAggregator(
        converter: converter,
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: expenses,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      // 10 USD * 7.2 = 72 CNY
      expect(report.total.amount, Decimal.parse('72.0'));
      expect(report.skippedFxCount, 0);
    });

    test('skips expenses lacking an FX rate and counts them', () {
      final converter = _converterWithRates(const []);
      final expenses = [
        _expense(
          id: 'e1',
          expenseAccountId: 'food',
          amount: Decimal.parse('1'),
          date: DateTime.utc(2026, 4, 5),
          currency: 'EUR',
        ),
        _expense(
          id: 'e2',
          expenseAccountId: 'food',
          amount: Decimal.parse('20'),
          date: DateTime.utc(2026, 4, 6),
        ),
      ];
      final aggregator = ExpenseReportAggregator(
        converter: converter,
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: expenses,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      expect(report.total.amount, Decimal.parse('20'));
      expect(report.skippedFxCount, 1);
    });

    test('drops expenses outside the range', () {
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: [
          _expense(
            id: 'before',
            expenseAccountId: 'food',
            amount: Decimal.parse('999'),
            date: DateTime.utc(2025, 12, 1),
          ),
          _expense(
            id: 'inside',
            expenseAccountId: 'food',
            amount: Decimal.parse('10'),
            date: DateTime.utc(2026, 4, 5),
          ),
          _expense(
            id: 'after',
            expenseAccountId: 'food',
            amount: Decimal.parse('999'),
            date: DateTime.utc(2027, 1, 1),
          ),
        ],
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      expect(report.total.amount, Decimal.parse('10'));
      expect(report.byCategory.single.items.single.id, 'inside');
    });

    test('renders empty report when no expenses fall in range', () {
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: const [],
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.m3,
          now: DateTime.utc(2026, 4, 17),
        ),
      );
      expect(report.isEmpty, isTrue);
      expect(report.total.amount, Decimal.zero);
      expect(report.monthlyBuckets.length, 3); // still seeded with zeros
      expect(
        report.monthlyBuckets.every((b) => b.total.amount == Decimal.zero),
        isTrue,
      );
    });
  });
}
