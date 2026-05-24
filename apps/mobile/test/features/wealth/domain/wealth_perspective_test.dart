import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/wealth/domain/wealth_perspective.dart';

Money _cny(String amount) => Money(Decimal.parse(amount), 'CNY');

CategoryItem _item({
  required String id,
  required String inBase,
  required String currency,
  required String nativeAmount,
}) {
  return CategoryItem(
    id: id,
    name: id,
    subtitle: null,
    valueInBase: _cny(inBase),
    nativeAmount: Decimal.parse(nativeAmount),
    nativeCurrency: currency,
  );
}

DashboardSnapshot _snapshot({required List<CategoryAllocation> allocations}) {
  Decimal totalAssets = Decimal.zero;
  Decimal totalLiabilities = Decimal.zero;
  for (final allocation in allocations) {
    if (allocation.category == AssetCategory.liability) {
      totalLiabilities += allocation.totalInBase.amount;
    } else {
      totalAssets += allocation.totalInBase.amount;
    }
  }
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 24),
    baseCurrency: 'CNY',
    allocations: allocations,
    totalAssets: _cny(totalAssets.toString()),
    totalLiabilities: _cny(totalLiabilities.toString()),
    netWorth: _cny((totalAssets - totalLiabilities).toString()),
  );
}

void main() {
  group('buildWealthAggregation byCategory', () {
    test('returns one bucket per non-liability category, sorted desc', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.cash,
            totalInBase: _cny('5000'),
            items: [_item(id: 'cny', inBase: '5000', currency: 'CNY', nativeAmount: '5000')],
          ),
          CategoryAllocation(
            category: AssetCategory.stock,
            totalInBase: _cny('20000'),
            items: [
              _item(id: 'aapl', inBase: '12000', currency: 'USD', nativeAmount: '160'),
              _item(id: 'tsla', inBase: '8000', currency: 'USD', nativeAmount: '110'),
            ],
          ),
          CategoryAllocation(
            category: AssetCategory.liability,
            totalInBase: _cny('3000'),
            items: const [],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCategory,
      );

      expect(agg.perspective, WealthPerspective.byCategory);
      expect(agg.buckets, hasLength(2));
      // Sorted descending by amount in base currency.
      expect(agg.buckets[0].key, 'stock');
      expect(agg.buckets[0].valueInBase.amount, Decimal.parse('20000'));
      expect(agg.buckets[0].itemCount, 2);
      expect(agg.buckets[1].key, 'cash');
      expect(agg.buckets[1].valueInBase.amount, Decimal.parse('5000'));
      // Total is the sum of asset buckets only — liabilities excluded.
      expect(agg.total.amount, Decimal.parse('25000'));
    });

    test('uses the supplied category label resolver', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.stock,
            totalInBase: _cny('1'),
            items: [_item(id: 'a', inBase: '1', currency: 'CNY', nativeAmount: '1')],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCategory,
        categoryLabel: (c) => c == AssetCategory.stock ? 'Stocks (i18n)' : c.name,
      );

      expect(agg.buckets.single.label, 'Stocks (i18n)');
    });

    test('drops zero-valued category buckets', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.stock,
            totalInBase: _cny('0'),
            items: const [],
          ),
          CategoryAllocation(
            category: AssetCategory.cash,
            totalInBase: _cny('1'),
            items: [_item(id: 'cny', inBase: '1', currency: 'CNY', nativeAmount: '1')],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCategory,
      );

      expect(agg.buckets, hasLength(1));
      expect(agg.buckets.single.key, 'cash');
    });
  });

  group('buildWealthAggregation byCurrency', () {
    test('groups item amounts across categories by native currency', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.stock,
            totalInBase: _cny('14000'),
            items: [
              _item(id: 'aapl', inBase: '12000', currency: 'USD', nativeAmount: '160'),
              _item(id: '600519', inBase: '2000', currency: 'CNY', nativeAmount: '2000'),
            ],
          ),
          CategoryAllocation(
            category: AssetCategory.crypto,
            totalInBase: _cny('6000'),
            items: [
              _item(id: 'btc', inBase: '6000', currency: 'USD', nativeAmount: '0.1'),
            ],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCurrency,
      );

      expect(agg.buckets, hasLength(2));
      // USD bucket aggregates 12k + 6k = 18k from two categories, two items.
      final usd = agg.buckets.firstWhere((b) => b.key == 'USD');
      expect(usd.valueInBase.amount, Decimal.parse('18000'));
      expect(usd.itemCount, 2);
      // CNY bucket holds just the single A-share entry.
      final cny = agg.buckets.firstWhere((b) => b.key == 'CNY');
      expect(cny.valueInBase.amount, Decimal.parse('2000'));
      expect(cny.itemCount, 1);
      // Sorted descending.
      expect(agg.buckets.first.key, 'USD');
    });

    test('normalises currency codes to uppercase', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.cash,
            totalInBase: _cny('100'),
            items: [
              _item(id: 'a', inBase: '50', currency: 'usd', nativeAmount: '7'),
              _item(id: 'b', inBase: '50', currency: 'USD', nativeAmount: '7'),
            ],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCurrency,
      );

      expect(agg.buckets, hasLength(1));
      expect(agg.buckets.single.key, 'USD');
      expect(agg.buckets.single.itemCount, 2);
    });

    test('liability category items are excluded from totals', () {
      final snapshot = _snapshot(
        allocations: [
          CategoryAllocation(
            category: AssetCategory.cash,
            totalInBase: _cny('100'),
            items: [
              _item(id: 'a', inBase: '100', currency: 'CNY', nativeAmount: '100'),
            ],
          ),
          CategoryAllocation(
            category: AssetCategory.liability,
            totalInBase: _cny('40'),
            items: [
              _item(id: 'l', inBase: '40', currency: 'CNY', nativeAmount: '40'),
            ],
          ),
        ],
      );

      final agg = buildWealthAggregation(
        snapshot: snapshot,
        perspective: WealthPerspective.byCurrency,
      );

      // Only the asset-side CNY shows; the liability item never enters.
      expect(agg.buckets.single.valueInBase.amount, Decimal.parse('100'));
      expect(agg.total.amount, Decimal.parse('100'));
    });
  });

  test('empty snapshot returns empty buckets and zero total', () {
    final agg = buildWealthAggregation(
      snapshot: _snapshot(allocations: const []),
      perspective: WealthPerspective.byCategory,
    );
    expect(agg.buckets, isEmpty);
    expect(agg.total.amount, Decimal.zero);
  });
}
