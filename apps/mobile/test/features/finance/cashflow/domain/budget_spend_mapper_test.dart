import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_spend_mapper.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 1),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

Expense _expense({
  required String categoryId,
  required String amount,
  String currency = 'CNY',
  DateTime? date,
}) => Expense(
  id: '$categoryId-$amount',
  categoryId: categoryId,
  amount: Decimal.parse(amount),
  currency: currency,
  tradeDate: date ?? DateTime.utc(2026, 5, 10),
  sync: _meta(),
);

void main() {
  group('buildBudgetSpendByCategoryId', () {
    test('aggregates same-month spend by expense account id', () {
      final spend = buildBudgetSpendByCategoryId(
        periodMonth: '2026-05',
        expenses: [
          _expense(categoryId: 'food', amount: '120'),
          _expense(categoryId: 'food', amount: '30'),
          _expense(categoryId: 'rent', amount: '5000'),
          _expense(
            categoryId: 'food',
            amount: '999',
            date: DateTime.utc(2026, 4, 30),
          ),
        ],
        targetCurrency: 'CNY',
        converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      );

      expect(spend['food'], Money.parse('150', 'CNY'));
      expect(spend['rent'], Money.parse('5000', 'CNY'));
      expect(spend, isNot(contains('other')));
    });

    test('converts foreign-currency expenses into target currency', () {
      final spend = buildBudgetSpendByCategoryId(
        periodMonth: '2026-05',
        expenses: [
          _expense(categoryId: 'travel', amount: '10', currency: 'USD'),
        ],
        targetCurrency: 'CNY',
        converter: FxRateCurrencyConverter(
          InMemoryFxRateLookup([
            FxRate(
              base: 'USD',
              quote: 'CNY',
              date: DateTime.utc(2026, 5, 1),
              rate: Decimal.parse('7.2'),
              source: 'test',
            ),
          ]),
        ),
      );

      expect(spend['travel'], Money.parse('72', 'CNY'));
    });

    test('skips expenses when FX is missing', () {
      final spend = buildBudgetSpendByCategoryId(
        periodMonth: '2026-05',
        expenses: [
          _expense(categoryId: 'travel', amount: '10', currency: 'USD'),
        ],
        targetCurrency: 'CNY',
        converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      );

      expect(spend, isEmpty);
    });
  });
}
