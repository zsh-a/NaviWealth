import 'package:decimal/decimal.dart';

import '../../../domain/values/money.dart';
import '../../home/domain/dashboard_models.dart';

/// User-configured target weights. Category targets represent broad
/// buckets; asset targets carve specific holdings out into their own
/// portfolio-level targets.
class TargetAllocation {
  const TargetAllocation({required this.weights, this.assetTargets = const {}});

  /// Map of category → target weight (0.0–1.0). Sum must equal 1.0.
  final Map<AssetCategory, double> weights;

  /// Map of asset id → portfolio-level target. These targets are counted
  /// separately from category targets and excluded from the category's
  /// actual residual when drift is computed.
  final Map<String, AssetTargetAllocation> assetTargets;

  double operator [](AssetCategory cat) => weights[cat] ?? 0;

  double assetWeight(String assetId) => assetTargets[assetId]?.weight ?? 0;

  bool get isValid {
    final sum =
        weights.values.fold<double>(0, (a, b) => a + b) +
        assetTargets.values.fold<double>(0, (a, b) => a + b.weight);
    return (sum - 1.0).abs() < 0.001;
  }

  /// Serialize to JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'categories': {for (final e in weights.entries) e.key.name: e.value},
    'assets': {for (final e in assetTargets.entries) e.key: e.value.toJson()},
  };

  /// Deserialize from JSON map.
  factory TargetAllocation.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final categoryJson = rawCategories is Map<String, dynamic>
        ? rawCategories
        : const <String, dynamic>{};
    final weights = <AssetCategory, double>{};
    for (final cat in AssetCategory.values) {
      final val = categoryJson[cat.name];
      if (val != null) {
        weights[cat] = (val as num).toDouble();
      }
    }
    final rawAssets = json['assets'];
    final assetTargets = <String, AssetTargetAllocation>{};
    if (rawAssets is Map<String, dynamic>) {
      for (final entry in rawAssets.entries) {
        final raw = entry.value;
        if (raw is! Map<String, dynamic>) continue;
        final target = AssetTargetAllocation.fromJson(entry.key, raw);
        assetTargets[target.assetId] = target;
      }
    }
    return TargetAllocation(weights: weights, assetTargets: assetTargets);
  }
}

/// Portfolio-level target for one concrete asset / holding.
class AssetTargetAllocation {
  const AssetTargetAllocation({
    required this.assetId,
    required this.label,
    required this.category,
    required this.weight,
  });

  final String assetId;
  final String label;
  final AssetCategory category;
  final double weight;

  Map<String, dynamic> toJson() => {
    'label': label,
    'category': category.name,
    'weight': weight,
  };

  factory AssetTargetAllocation.fromJson(
    String assetId,
    Map<String, dynamic> json,
  ) {
    final categoryName = json['category'];
    final category = AssetCategory.values.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => AssetCategory.stock,
    );
    return AssetTargetAllocation(
      assetId: assetId,
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? (json['label'] as String).trim()
          : assetId,
      category: category,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
    );
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
    this.assetId,
    this.assetLabel,
  });

  final AssetCategory category;
  final String? assetId;
  final String? assetLabel;

  bool get isAssetTarget => assetId != null;

  String? get targetLabel => assetLabel;

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
    this.assetId,
    this.assetLabel,
    this.description,
  });

  final AssetCategory category;
  final String? assetId;
  final String? assetLabel;
  final TradeDirection direction;

  bool get isAssetTarget => assetId != null;

  String? get targetLabel => assetLabel;

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
