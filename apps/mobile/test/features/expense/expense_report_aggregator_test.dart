import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/expense.dart';
import 'package:naviwealth/data/domain/expense_category.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/features/expense/domain/expense_report_aggregator.dart';
import 'package:naviwealth/features/expense/domain/expense_report_range.dart';

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

ExpenseCategory _cat(String id, {String? parent, String? name}) =>
    ExpenseCategory(
      id: id,
      name: name ?? id,
      parentId: parent,
      sync: _meta(),
    );

Expense _expense({
  required String id,
  required String categoryId,
  required Decimal amount,
  required DateTime date,
  String currency = 'CNY',
}) =>
    Expense(
      id: id,
      accountId: 'acct-1',
      categoryId: categoryId,
      amount: amount,
      currency: currency,
      tradeDate: date,
      sync: _meta(),
    );

CurrencyConverter _converterWithRates(Iterable<FxRate> rates) =>
    FxRateCurrencyConverter(InMemoryFxRateLookup(rates));

void main() {
  group('ExpenseReportAggregator', () {
    test('rolls expenses into top-level categories sorted by total', () {
      final categories = [
        _cat('food', name: '餐饮'),
        _cat('transport', name: '交通'),
      ];
      final expenses = [
        _expense(
          id: 'e1',
          categoryId: 'food',
          amount: Decimal.parse('120'),
          date: DateTime.utc(2026, 4, 5),
        ),
        _expense(
          id: 'e2',
          categoryId: 'food',
          amount: Decimal.parse('80'),
          date: DateTime.utc(2026, 4, 10),
        ),
        _expense(
          id: 'e3',
          categoryId: 'transport',
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
        categories: categories,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      expect(report.total.amount, Decimal.parse('250'));
      expect(report.byCategory.length, 2);
      expect(report.byCategory.first.categoryId, 'food');
      expect(report.byCategory.first.total.amount, Decimal.parse('200'));
      expect(report.byCategory.first.items.length, 2);
      expect(report.byCategory[1].categoryId, 'transport');
    });

    test('flattens sub-categories into their top-level parent for the pie',
        () {
      final categories = [
        _cat('food', name: '餐饮'),
        _cat('food.lunch', parent: 'food', name: '午餐'),
        _cat('food.dinner', parent: 'food', name: '晚餐'),
      ];
      final expenses = [
        _expense(
          id: 'e1',
          categoryId: 'food.lunch',
          amount: Decimal.parse('30'),
          date: DateTime.utc(2026, 4, 1),
        ),
        _expense(
          id: 'e2',
          categoryId: 'food.dinner',
          amount: Decimal.parse('70'),
          date: DateTime.utc(2026, 4, 2),
        ),
        _expense(
          id: 'e3',
          categoryId: 'food',
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
        categories: categories,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 15),
        ),
      );
      expect(report.byCategory.length, 1);
      final food = report.byCategory.single;
      expect(food.categoryId, 'food');
      expect(food.total.amount, Decimal.parse('115'));
      expect(food.items.length, 3);
      // Sub-categories: dinner (70) > lunch (30); top-level direct entry
      // should not appear under subCategories.
      expect(food.subCategories.length, 2);
      expect(food.subCategories.first.categoryId, 'food.dinner');
      expect(food.subCategories.first.total.amount, Decimal.parse('70'));
      expect(food.subCategories[1].categoryId, 'food.lunch');
    });

    test('zero-fills monthly buckets across the range', () {
      final categories = [_cat('food')];
      final expenses = [
        _expense(
          id: 'e-jan',
          categoryId: 'food',
          amount: Decimal.parse('100'),
          date: DateTime.utc(2026, 2, 5),
        ),
        _expense(
          id: 'e-mar',
          categoryId: 'food',
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
        categories: categories,
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
      final categories = [_cat('food')];
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
          categoryId: 'food',
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
        categories: categories,
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
      final categories = [_cat('food')];
      final converter = _converterWithRates(const []);
      final expenses = [
        _expense(
          id: 'e1',
          categoryId: 'food',
          amount: Decimal.parse('1'),
          date: DateTime.utc(2026, 4, 5),
          currency: 'EUR',
        ),
        _expense(
          id: 'e2',
          categoryId: 'food',
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
        categories: categories,
        range: ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.monthToDate,
          now: DateTime.utc(2026, 4, 30),
        ),
      );
      expect(report.total.amount, Decimal.parse('20'));
      expect(report.skippedFxCount, 1);
    });

    test('drops expenses outside the range', () {
      final categories = [_cat('food')];
      final aggregator = ExpenseReportAggregator(
        converter: _converterWithRates(const []),
        baseCurrency: 'CNY',
      );
      final report = aggregator.aggregate(
        expenses: [
          _expense(
            id: 'before',
            categoryId: 'food',
            amount: Decimal.parse('999'),
            date: DateTime.utc(2025, 12, 1),
          ),
          _expense(
            id: 'inside',
            categoryId: 'food',
            amount: Decimal.parse('10'),
            date: DateTime.utc(2026, 4, 5),
          ),
          _expense(
            id: 'after',
            categoryId: 'food',
            amount: Decimal.parse('999'),
            date: DateTime.utc(2027, 1, 1),
          ),
        ],
        categories: categories,
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
        categories: const [],
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
