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
    final actualWeights = _computeActualWeights(snapshot, totalAssets);
    final drifts = _computeDrifts(actualWeights, target);
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
    Money totalAssets,
  ) {
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
      weights[alloc.category] = alloc.totalInBase.amount.toDouble() / total;
    }
    // Ensure all non-liability categories are present.
    for (final cat in AssetCategory.values) {
      if (cat != AssetCategory.liability) {
        weights.putIfAbsent(cat, () => 0);
      }
    }
    return weights;
  }

  /// Compute per-category drift against the target.
  List<Drift> _computeDrifts(
    Map<AssetCategory, double> actual,
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
      if (drift.deviation <= 0) continue;
      final sellAmount = total * Decimal.parse(drift.deviation.toString());
      if (sellAmount <= Decimal.zero) continue;
      trades.add(
        SuggestedTrade(
          category: drift.category,
          direction: TradeDirection.sell,
          amount: Money(sellAmount, totalAssets.currency),
        ),
      );
    }

    // Then buy underweight categories.
    for (final drift in drifts) {
      if (drift.deviation >= 0) continue;
      final buyAmount = total * Decimal.parse((-drift.deviation).toString());
      if (buyAmount <= Decimal.zero) continue;
      trades.add(
        SuggestedTrade(
          category: drift.category,
          direction: TradeDirection.buy,
          amount: Money(buyAmount, totalAssets.currency),
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
