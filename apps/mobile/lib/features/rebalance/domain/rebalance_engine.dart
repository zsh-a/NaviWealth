import 'package:decimal/decimal.dart';

import '../../../domain/values/money.dart';
import '../../home/domain/dashboard_models.dart';
import 'rebalance_models.dart';

/// Pure domain engine that computes drift and generates suggested trades.
///
/// No Flutter or Riverpod dependency — unit-testable with plain Dart.
class RebalanceEngine {
  const RebalanceEngine({
    this.warningThreshold = 0.05,
    this.criticalThreshold = 0.10,
    this.estimatedFeeRate = 0.001,
    this.estimatedTaxRate = 0.001,
  });

  /// Absolute deviation at which a category gets a [DriftSeverity.warning].
  final double warningThreshold;

  /// Absolute deviation at which a category gets [DriftSeverity.critical].
  final double criticalThreshold;

  /// Approximate fee rate applied to trade amounts (0.1% default).
  final double estimatedFeeRate;

  /// Approximate tax rate applied to sell amounts (0.1% default).
  final double estimatedTaxRate;

  /// Compute a full [RebalancePlan] from the current allocation snapshot
  /// and the user's target weights.
  RebalancePlan compute({
    required DashboardSnapshot snapshot,
    required TargetAllocation target,
  }) {
    final totalAssets = snapshot.totalAssets;
    final targetedAssetIds = target.assetTargets.keys.toSet();
    final actualWeights = _computeActualWeights(
      snapshot,
      totalAssets,
      excludedAssetIds: targetedAssetIds,
    );
    final actualAssetWeights = _computeActualAssetWeights(
      snapshot,
      totalAssets,
      target,
    );
    final drifts = _computeDrifts(actualWeights, actualAssetWeights, target);
    final trades = _generateTrades(drifts, totalAssets, target);
    final fees = _estimateFees(trades, totalAssets.currency);
    final taxes = _estimateTaxes(trades, totalAssets.currency);
    final driftBefore = _overallDrift(drifts);
    final driftAfter = _estimateDriftAfter(trades, totalAssets, target);

    return RebalancePlan(
      target: target,
      actualWeights: actualWeights,
      drifts: drifts,
      trades: trades,
      estimatedFees: fees,
      estimatedTaxes: taxes,
      driftBeforePct: driftBefore,
      driftAfterPct: driftAfter,
      totalAssets: totalAssets,
    );
  }

  /// Compute actual weights from the dashboard snapshot. Only asset
  /// categories (not liabilities) are included.
  Map<AssetCategory, double> _computeActualWeights(
    DashboardSnapshot snapshot,
    Money totalAssets, {
    Set<String> excludedAssetIds = const {},
  }) {
    if (totalAssets.amount <= Decimal.zero) {
      return {
        for (final cat in AssetCategory.values)
          if (cat != AssetCategory.liability) cat: 0.0,
      };
    }
    final total = totalAssets.amount.toDouble();
    final weights = <AssetCategory, double>{};
    for (final alloc in snapshot.allocations) {
      if (alloc.isLiability) continue;
      final includedTotal = alloc.items.fold<Decimal>(
        Decimal.zero,
        (sum, item) => excludedAssetIds.contains(item.id)
            ? sum
            : sum + item.valueInBase.amount,
      );
      weights[alloc.category] = includedTotal.toDouble() / total;
    }
    // Ensure all non-liability categories are present.
    for (final cat in AssetCategory.values) {
      if (cat != AssetCategory.liability) {
        weights.putIfAbsent(cat, () => 0);
      }
    }
    return weights;
  }

  /// Compute actual weights for explicitly targeted assets. Missing assets
  /// are retained with zero weight so the user sees that the target is
  /// underweight rather than silently disappearing.
  List<_AssetActualWeight> _computeActualAssetWeights(
    DashboardSnapshot snapshot,
    Money totalAssets,
    TargetAllocation target,
  ) {
    final itemById = <String, ({CategoryItem item, AssetCategory category})>{};
    for (final alloc in snapshot.allocations) {
      if (alloc.isLiability) continue;
      for (final item in alloc.items) {
        itemById[item.id] = (item: item, category: alloc.category);
      }
    }

    final total = totalAssets.amount.toDouble();
    return [
      for (final targetAsset in target.assetTargets.values)
        _AssetActualWeight(
          assetId: targetAsset.assetId,
          label: itemById[targetAsset.assetId]?.item.name ?? targetAsset.label,
          category:
              itemById[targetAsset.assetId]?.category ?? targetAsset.category,
          actualWeight: totalAssets.amount <= Decimal.zero
              ? 0
              : (itemById[targetAsset.assetId]?.item.valueInBase.amount
                            .toDouble() ??
                        0) /
                    total,
          targetWeight: targetAsset.weight,
        ),
    ];
  }

  /// Compute drift against category and asset-level targets.
  List<Drift> _computeDrifts(
    Map<AssetCategory, double> actual,
    List<_AssetActualWeight> actualAssets,
    TargetAllocation target,
  ) {
    final drifts = <Drift>[];
    for (final cat in AssetCategory.values) {
      if (cat == AssetCategory.liability) continue;
      final actualW = actual[cat] ?? 0;
      final targetW = target[cat];
      final dev = actualW - targetW;
      final severity = _severity(dev.abs());
      drifts.add(
        Drift(
          category: cat,
          actualWeight: actualW,
          targetWeight: targetW,
          severity: severity,
        ),
      );
    }
    for (final asset in actualAssets) {
      final dev = asset.actualWeight - asset.targetWeight;
      drifts.add(
        Drift(
          category: asset.category,
          assetId: asset.assetId,
          assetLabel: asset.label,
          actualWeight: asset.actualWeight,
          targetWeight: asset.targetWeight,
          severity: _severity(dev.abs()),
        ),
      );
    }
    return drifts;
  }

  DriftSeverity _severity(double absDev) {
    if (absDev >= criticalThreshold) return DriftSeverity.critical;
    if (absDev >= warningThreshold) return DriftSeverity.warning;
    return DriftSeverity.ok;
  }

  /// Generate buy/sell suggestions. Sells first, then buys.
  List<SuggestedTrade> _generateTrades(
    List<Drift> drifts,
    Money totalAssets,
    TargetAllocation target,
  ) {
    if (totalAssets.amount <= Decimal.zero) return const [];

    final trades = <SuggestedTrade>[];
    final total = totalAssets.amount;

    // Sell overweight categories first.
    for (final drift in drifts) {
      if (drift.severity == DriftSeverity.ok) continue;
      if (drift.deviation <= 0) continue;
      final sellAmount = total * Decimal.parse(drift.deviation.toString());
      if (sellAmount <= Decimal.zero) continue;
      trades.add(
        SuggestedTrade(
          category: drift.category,
          assetId: drift.assetId,
          assetLabel: drift.assetLabel,
          direction: TradeDirection.sell,
          amount: Money(sellAmount, totalAssets.currency),
          description: drift.assetLabel,
        ),
      );
    }

    // Then buy underweight categories.
    for (final drift in drifts) {
      if (drift.severity == DriftSeverity.ok) continue;
      if (drift.deviation >= 0) continue;
      final buyAmount = total * Decimal.parse((-drift.deviation).toString());
      if (buyAmount <= Decimal.zero) continue;
      trades.add(
        SuggestedTrade(
          category: drift.category,
          assetId: drift.assetId,
          assetLabel: drift.assetLabel,
          direction: TradeDirection.buy,
          amount: Money(buyAmount, totalAssets.currency),
          description: drift.assetLabel,
        ),
      );
    }

    return trades;
  }

  Money _estimateFees(List<SuggestedTrade> trades, String fallbackCurrency) {
    if (trades.isEmpty) {
      return Money.zero(fallbackCurrency);
    }
    final currency = trades.first.amount.currency;
    var totalFee = Decimal.zero;
    for (final trade in trades) {
      totalFee +=
          trade.amount.amount * Decimal.parse(estimatedFeeRate.toString());
    }
    return Money(totalFee, currency);
  }

  Money _estimateTaxes(List<SuggestedTrade> trades, String fallbackCurrency) {
    if (trades.isEmpty) {
      return Money.zero(fallbackCurrency);
    }
    final currency = trades.first.amount.currency;
    var totalTax = Decimal.zero;
    for (final trade in trades) {
      if (trade.isSell) {
        totalTax +=
            trade.amount.amount * Decimal.parse(estimatedTaxRate.toString());
      }
    }
    return Money(totalTax, currency);
  }

  /// One-sided drift: sum(|deviation|) / 2.
  double _overallDrift(List<Drift> drifts) {
    return drifts.fold<double>(0, (sum, d) => sum + d.absDeviation) / 2;
  }

  /// Estimate drift after all trades execute.
  double _estimateDriftAfter(
    List<SuggestedTrade> trades,
    Money totalAssets,
    TargetAllocation target,
  ) {
    if (totalAssets.amount <= Decimal.zero) return 0;
    // After perfect rebalance, drift → 0. Estimate with a small residual
    // due to rounding and fee drag.
    final feeDrag =
        _estimateFees(trades, totalAssets.currency).amount.toDouble() /
        totalAssets.amount.toDouble();
    return feeDrag;
  }
}

class _AssetActualWeight {
  const _AssetActualWeight({
    required this.assetId,
    required this.label,
    required this.category,
    required this.actualWeight,
    required this.targetWeight,
  });

  final String assetId;
  final String label;
  final AssetCategory category;
  final double actualWeight;
  final double targetWeight;
}
