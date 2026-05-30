import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_engine.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';

void main() {
  test('empty trade fee estimates keep the snapshot base currency', () {
    final snapshot = DashboardSnapshot(
      asOf: DateTime.utc(2026, 5, 30),
      baseCurrency: 'USD',
      allocations: [
        CategoryAllocation(
          category: AssetCategory.cash,
          totalInBase: Money(Decimal.parse('1000'), 'USD'),
          items: const [],
        ),
      ],
      totalAssets: Money(Decimal.parse('1000'), 'USD'),
      totalLiabilities: Money.zero('USD'),
      netWorth: Money(Decimal.parse('1000'), 'USD'),
    );
    final target = TargetAllocation(
      weights: {
        for (final category in AssetCategory.values)
          if (category != AssetCategory.liability) category: 0,
        AssetCategory.cash: 1,
      },
    );

    final plan = const RebalanceEngine().compute(
      snapshot: snapshot,
      target: target,
    );

    expect(plan.trades, isEmpty);
    expect(plan.estimatedFees.currency, 'USD');
    expect(plan.estimatedTaxes.currency, 'USD');
  });
}
