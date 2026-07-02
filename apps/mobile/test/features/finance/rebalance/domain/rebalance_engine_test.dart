import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/rebalance/domain/allocation_schemes.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';

void main() {
  test('built-in allocation presets are valid full allocations', () {
    for (final preset in AllocationSchemePreset.values) {
      final allocation = allocationScheme(preset);

      expect(allocation.isValid, isTrue, reason: preset.name);
      expect(
        allocation.weights.keys,
        containsAll(
          AssetCategory.values.where((c) => c != AssetCategory.liability),
        ),
        reason: preset.name,
      );
      expect(allocation[AssetCategory.liability], 0);
    }
  });

  test('custom allocation starts from balanced as an editable template', () {
    final custom = allocationScheme(AllocationSchemePreset.custom);
    final balanced = allocationScheme(AllocationSchemePreset.balanced);

    expect(custom.weights, balanced.weights);
    expect(custom.assetTargets, isEmpty);
  });

  test('target allocation serializes category and asset targets', () {
    final allocation = TargetAllocation(
      weights: {
        for (final category in AssetCategory.values)
          if (category != AssetCategory.liability) category: 0,
        AssetCategory.cash: 0.5,
      },
      assetTargets: const {
        'qqq': AssetTargetAllocation(
          assetId: 'qqq',
          label: 'QQQ',
          category: AssetCategory.etf,
          weight: 0.5,
        ),
      },
    );

    final roundTrip = TargetAllocation.fromJson(allocation.toJson());

    expect(roundTrip.isValid, isTrue);
    expect(roundTrip[AssetCategory.cash], 0.5);
    expect(roundTrip.assetTargets['qqq']?.label, 'QQQ');
    expect(roundTrip.assetTargets['qqq']?.category, AssetCategory.etf);
    expect(roundTrip.assetTargets['qqq']?.weight, 0.5);
  });

  test('asset targets are excluded from category residual drift', () {
    final snapshot = DashboardSnapshot(
      asOf: DateTime.utc(2026, 5, 30),
      baseCurrency: 'USD',
      allocations: [
        CategoryAllocation(
          category: AssetCategory.etf,
          totalInBase: Money(Decimal.parse('800'), 'USD'),
          items: [
            CategoryItem(
              id: 'qqq',
              name: 'QQQ',
              subtitle: '10 · USD',
              valueInBase: Money(Decimal.parse('700'), 'USD'),
              nativeAmount: Decimal.parse('700'),
              nativeCurrency: 'USD',
            ),
            CategoryItem(
              id: 'voo',
              name: 'VOO',
              subtitle: '1 · USD',
              valueInBase: Money(Decimal.parse('100'), 'USD'),
              nativeAmount: Decimal.parse('100'),
              nativeCurrency: 'USD',
            ),
          ],
        ),
        CategoryAllocation(
          category: AssetCategory.cash,
          totalInBase: Money(Decimal.parse('200'), 'USD'),
          items: [
            CategoryItem(
              id: 'cash',
              name: 'Cash',
              subtitle: null,
              valueInBase: Money(Decimal.parse('200'), 'USD'),
              nativeAmount: Decimal.parse('200'),
              nativeCurrency: 'USD',
            ),
          ],
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
        AssetCategory.etf: 0.1,
        AssetCategory.cash: 0.4,
      },
      assetTargets: const {
        'qqq': AssetTargetAllocation(
          assetId: 'qqq',
          label: 'QQQ',
          category: AssetCategory.etf,
          weight: 0.5,
        ),
      },
    );

    final plan = const RebalanceEngine(
      warningThreshold: 0.01,
    ).compute(snapshot: snapshot, target: target);
    final etfResidual = plan.drifts.singleWhere(
      (d) => d.category == AssetCategory.etf && !d.isAssetTarget,
    );
    final qqq = plan.drifts.singleWhere((d) => d.assetId == 'qqq');
    final cash = plan.drifts.singleWhere(
      (d) => d.category == AssetCategory.cash && !d.isAssetTarget,
    );

    expect(etfResidual.actualWeight, closeTo(0.1, 0.0001));
    expect(etfResidual.targetWeight, 0.1);
    expect(etfResidual.severity, DriftSeverity.ok);
    expect(qqq.actualWeight, closeTo(0.7, 0.0001));
    expect(qqq.targetWeight, 0.5);
    expect(cash.actualWeight, closeTo(0.2, 0.0001));
    expect(cash.targetWeight, 0.4);
    expect(plan.trades.where((t) => t.assetId == 'qqq'), hasLength(1));
    expect(plan.trades.singleWhere((t) => t.assetId == 'qqq').isSell, isTrue);
  });

  test('drifts below warning threshold do not generate noise trades', () {
    final snapshot = DashboardSnapshot(
      asOf: DateTime.utc(2026, 5, 30),
      baseCurrency: 'USD',
      allocations: [
        CategoryAllocation(
          category: AssetCategory.stock,
          totalInBase: Money(Decimal.parse('520'), 'USD'),
          items: [
            CategoryItem(
              id: 'stock',
              name: 'Stock',
              subtitle: null,
              valueInBase: Money(Decimal.parse('520'), 'USD'),
              nativeAmount: Decimal.parse('520'),
              nativeCurrency: 'USD',
            ),
          ],
        ),
        CategoryAllocation(
          category: AssetCategory.cash,
          totalInBase: Money(Decimal.parse('480'), 'USD'),
          items: [
            CategoryItem(
              id: 'cash',
              name: 'Cash',
              subtitle: null,
              valueInBase: Money(Decimal.parse('480'), 'USD'),
              nativeAmount: Decimal.parse('480'),
              nativeCurrency: 'USD',
            ),
          ],
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
        AssetCategory.stock: 0.5,
        AssetCategory.cash: 0.5,
      },
    );

    final plan = const RebalanceEngine(
      warningThreshold: 0.05,
    ).compute(snapshot: snapshot, target: target);

    expect(plan.isBalanced, isTrue);
    expect(plan.drifts.where((d) => d.severity != DriftSeverity.ok), isEmpty);
    expect(plan.trades, isEmpty);
    expect(plan.estimatedFees, Money.zero('USD'));
    expect(plan.estimatedTaxes, Money.zero('USD'));
  });

  test('empty trade fee estimates keep the snapshot base currency', () {
    final snapshot = DashboardSnapshot(
      asOf: DateTime.utc(2026, 5, 30),
      baseCurrency: 'USD',
      allocations: [
        CategoryAllocation(
          category: AssetCategory.cash,
          totalInBase: Money(Decimal.parse('1000'), 'USD'),
          items: [
            CategoryItem(
              id: 'cash',
              name: 'Cash',
              subtitle: null,
              valueInBase: Money(Decimal.parse('1000'), 'USD'),
              nativeAmount: Decimal.parse('1000'),
              nativeCurrency: 'USD',
            ),
          ],
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
