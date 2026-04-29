import 'package:decimal/decimal.dart';

import '../../../domain/values/money.dart';
import '../../home/domain/dashboard_models.dart';

/// User-configured target weight for a single [AssetCategory].
class TargetAllocation {
  const TargetAllocation({required this.weights});

  /// Map of category → target weight (0.0–1.0). Sum must equal 1.0.
  final Map<AssetCategory, double> weights;

  double operator [](AssetCategory cat) => weights[cat] ?? 0;

  bool get isValid {
    final sum = weights.values.fold<double>(0, (a, b) => a + b);
    return (sum - 1.0).abs() < 0.001;
  }

  /// Serialize to JSON-compatible map (key = category name).
  Map<String, dynamic> toJson() => {
    for (final e in weights.entries) e.key.name: e.value,
  };

  /// Deserialize from JSON map.
  factory TargetAllocation.fromJson(Map<String, dynamic> json) {
    final weights = <AssetCategory, double>{};
    for (final cat in AssetCategory.values) {
      final val = json[cat.name];
      if (val != null) {
        weights[cat] = (val as num).toDouble();
      }
    }
    return TargetAllocation(weights: weights);
  }
}

/// Severity level for drift — drives UI color.
enum DriftSeverity {
  /// Within acceptable range.
  ok,

  /// Exceeds the warning threshold (default ±5%).
  warning,

  /// Exceeds the critical threshold (default ±10%).
  critical,
}

/// Per-category deviation between actual and target allocation.
class Drift {
  const Drift({
    required this.category,
    required this.actualWeight,
    required this.targetWeight,
    required this.severity,
  });

  final AssetCategory category;

  /// Current portfolio weight (0.0–1.0).
  final double actualWeight;

  /// Target portfolio weight (0.0–1.0).
  final double targetWeight;

  /// Signed deviation: positive = overweight, negative = underweight.
  double get deviation => actualWeight - targetWeight;

  /// Absolute deviation.
  double get absDeviation => deviation.abs();

  /// How much money needs to move to reach target.
  Money deltaAmount(Money totalAssets) {
    final delta = Decimal.parse((targetWeight - actualWeight).toString());
    return totalAssets.scale(delta);
  }

  final DriftSeverity severity;
}

/// Direction of a suggested trade.
enum TradeDirection { buy, sell }

/// A single suggested trade to move the portfolio toward the target.
class SuggestedTrade {
  const SuggestedTrade({
    required this.category,
    required this.direction,
    required this.amount,
    this.description,
  });

  final AssetCategory category;
  final TradeDirection direction;

  /// Amount in base currency to buy or sell.
  final Money amount;

  /// Optional human-readable description (e.g. "Sell AAPL 20 shares").
  final String? description;

  bool get isBuy => direction == TradeDirection.buy;
  bool get isSell => direction == TradeDirection.sell;
}

/// The complete output of a rebalance computation.
class RebalancePlan {
  const RebalancePlan({
    required this.target,
    required this.actualWeights,
    required this.drifts,
    required this.trades,
    required this.estimatedFees,
    required this.estimatedTaxes,
    required this.driftBeforePct,
    required this.driftAfterPct,
    required this.totalAssets,
  });

  final TargetAllocation target;
  final Map<AssetCategory, double> actualWeights;
  final List<Drift> drifts;
  final List<SuggestedTrade> trades;
  final Money estimatedFees;
  final Money estimatedTaxes;

  /// Overall portfolio drift before rebalancing (one-sided, 0–100%).
  final double driftBeforePct;

  /// Estimated overall drift after executing all suggested trades.
  final double driftAfterPct;

  /// Total asset value in base currency.
  final Money totalAssets;

  /// Whether the portfolio is already within acceptable bounds.
  bool get isBalanced => drifts.every((d) => d.severity == DriftSeverity.ok);
}
