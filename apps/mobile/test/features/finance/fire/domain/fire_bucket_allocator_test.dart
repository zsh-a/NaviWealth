import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_bucket.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_bucket_allocator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';

CategoryItem _item(String id, String amount, {String currency = 'CNY'}) {
  return CategoryItem(
    id: id,
    name: id,
    subtitle: null,
    valueInBase: Money(Decimal.parse(amount), currency),
    nativeAmount: Decimal.parse(amount),
    nativeCurrency: currency,
  );
}

CategoryAllocation _alloc(
  AssetCategory cat,
  List<CategoryItem> items, {
  String currency = 'CNY',
}) {
  final total = items.fold<Decimal>(
    Decimal.zero,
    (sum, i) => sum + i.valueInBase.amount,
  );
  return CategoryAllocation(
    category: cat,
    totalInBase: Money(total, currency),
    items: items,
  );
}

DashboardSnapshot _snapshot(List<CategoryAllocation> allocations) {
  final totalAssets = allocations
      .where((a) => a.category != AssetCategory.liability)
      .fold<Decimal>(Decimal.zero, (sum, a) => sum + a.totalInBase.amount);
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 20),
    baseCurrency: 'CNY',
    allocations: allocations,
    totalAssets: Money(totalAssets, 'CNY'),
    totalLiabilities: Money.zero('CNY'),
    netWorth: Money(totalAssets, 'CNY'),
  );
}

FirePlan _plan({String monthlyExpenses = '4000', int cashBucketMonths = 12}) {
  return FirePlan.fromGoal(
    FireGoal(
      targetAmount: Decimal.parse('1000000'),
      monthlyExpenses: Decimal.parse(monthlyExpenses),
      monthlySurplus: Decimal.zero,
      inflationRate: 0,
    ),
    baseCurrency: 'CNY',
    targetCashBucketMonths: cashBucketMonths,
  );
}

void main() {
  group('allocateBuckets', () {
    test('default classifier slots each category into its expected role', () {
      final snap = _snapshot([
        _alloc(AssetCategory.cash, [_item('cash-1', '50000')]),
        _alloc(AssetCategory.bondsAndFunds, [_item('bond-1', '40000')]),
        _alloc(AssetCategory.stock, [_item('stock-1', '200000')]),
        _alloc(AssetCategory.etf, [_item('etf-1', '100000')]),
        _alloc(AssetCategory.crypto, [_item('btc', '20000')]),
      ]);
      final allocation = allocateBuckets(
        plan: _plan(),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
      );
      final byRole = {for (final b in allocation.buckets) b.role: b};
      expect(
        byRole[FireBucketRole.cash]!.currentValue.amount,
        Decimal.parse('50000'),
      );
      expect(
        byRole[FireBucketRole.defensive]!.currentValue.amount,
        Decimal.parse('40000'),
      );
      // stock + etf + crypto all map to growth by default.
      expect(
        byRole[FireBucketRole.growth]!.currentValue.amount,
        Decimal.parse('320000'),
      );
      expect(
        byRole[FireBucketRole.riskReserve]!.currentValue.amount,
        Decimal.zero,
      );
      expect(byRole[FireBucketRole.dream]!.currentValue.amount, Decimal.zero);
      expect(allocation.unmappedHoldings, isEmpty);
    });

    test('real estate and vehicles surface as unmapped by default', () {
      final snap = _snapshot([
        _alloc(AssetCategory.realEstate, [_item('house', '2000000')]),
        _alloc(AssetCategory.vehicle, [_item('car', '120000')]),
      ]);
      final allocation = allocateBuckets(
        plan: _plan(),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
      );
      expect(allocation.unmappedHoldings, hasLength(2));
      expect(allocation.unmappedHoldings.map((u) => u.id).toSet(), {
        'house',
        'car',
      });
      for (final bucket in allocation.buckets) {
        expect(bucket.currentValue.amount, Decimal.zero);
      }
    });

    test('user rules override category defaults', () {
      // A growth-default crypto holding gets pinned to risk reserve.
      final snap = _snapshot([
        _alloc(AssetCategory.crypto, [_item('btc', '50000')]),
      ]);
      final allocation = allocateBuckets(
        plan: _plan(),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
        userRules: [
          const FireBucketRule(
            id: 'btc',
            role: FireBucketRole.riskReserve,
            targetTable: 'assets',
            targetId: 'btc',
          ),
        ],
      );
      final byRole = {for (final b in allocation.buckets) b.role: b};
      expect(byRole[FireBucketRole.growth]!.currentValue.amount, Decimal.zero);
      expect(
        byRole[FireBucketRole.riskReserve]!.currentValue.amount,
        Decimal.parse('50000'),
      );
    });

    test(
      'allocationPct splits a holding across explicit + default fallback',
      () {
        // 50% to dream — the other 50% still counts? The model treats
        // unallocated remainder as ignored; the rule's pct directly
        // scales the contribution.
        final snap = _snapshot([
          _alloc(AssetCategory.realEstate, [_item('rental', '1000000')]),
        ]);
        final allocation = allocateBuckets(
          plan: _plan(),
          snapshot: snap,
          monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
          userRules: [
            const FireBucketRule(
              id: 'rental',
              role: FireBucketRole.dream,
              targetTable: 'assets',
              targetId: 'rental',
              allocationPct: 0.5,
            ),
          ],
        );
        final dream = allocation.buckets.firstWhere(
          (b) => b.role == FireBucketRole.dream,
        );
        expect(dream.currentValue.amount, Decimal.parse('500000'));
        expect(allocation.unmappedHoldings, isEmpty);
      },
    );

    test('cash bucket target = monthlyExpense × targetCashBucketMonths', () {
      final snap = _snapshot([
        _alloc(AssetCategory.cash, [_item('cash', '60000')]),
      ]);
      final allocation = allocateBuckets(
        plan: _plan(monthlyExpenses: '5000', cashBucketMonths: 12),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('5000'), 'CNY'),
      );
      final cash = allocation.buckets.firstWhere(
        (b) => b.role == FireBucketRole.cash,
      );
      expect(cash.targetValue.amount, Decimal.parse('60000'));
      expect(cash.status, FireBucketStatus.onTrack);
      expect(cash.coverageRatio, closeTo(1.0, 1e-9));
    });

    test('status flags under/over/empty correctly', () {
      // Cash bucket undertarget.
      var snap = _snapshot([
        _alloc(AssetCategory.cash, [_item('cash', '20000')]),
      ]);
      var allocation = allocateBuckets(
        plan: _plan(monthlyExpenses: '5000', cashBucketMonths: 12),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('5000'), 'CNY'),
      );
      var cash = allocation.buckets.firstWhere(
        (b) => b.role == FireBucketRole.cash,
      );
      expect(cash.status, FireBucketStatus.underTarget);

      // Cash bucket overtarget.
      snap = _snapshot([
        _alloc(AssetCategory.cash, [_item('cash', '100000')]),
      ]);
      allocation = allocateBuckets(
        plan: _plan(monthlyExpenses: '5000', cashBucketMonths: 12),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('5000'), 'CNY'),
      );
      cash = allocation.buckets.firstWhere(
        (b) => b.role == FireBucketRole.cash,
      );
      expect(cash.status, FireBucketStatus.overTarget);

      // Growth bucket without target → empty.
      final growth = allocation.buckets.firstWhere(
        (b) => b.role == FireBucketRole.growth,
      );
      expect(growth.status, FireBucketStatus.empty);
      expect(growth.coverageRatio, isNull);
    });

    test('liabilities are ignored entirely', () {
      final snap = _snapshot([
        _alloc(AssetCategory.cash, [_item('cash', '50000')]),
        _alloc(AssetCategory.liability, [_item('loan', '200000')]),
      ]);
      final allocation = allocateBuckets(
        plan: _plan(),
        snapshot: snap,
        monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
      );
      // The liability never shows up in any bucket or in the unmapped
      // list — it is handled at the net-worth level, not here.
      expect(
        allocation.buckets
            .firstWhere((b) => b.role == FireBucketRole.cash)
            .currentValue
            .amount,
        Decimal.parse('50000'),
      );
      expect(allocation.unmappedHoldings, isEmpty);
    });
  });
}
