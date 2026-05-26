import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/data/domain/asset.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import 'equity_allocation.dart';
import 'equity_classification.dart';

/// Severity of a concentration risk alert.
///
/// [warning] — the threshold is breached but not yet critical.
/// [critical] — the position is dangerously concentrated.
enum RiskSeverity { warning, critical }

/// The dimension along which concentration is measured.
enum RiskDimension {
  /// A single asset (stock / ETF / crypto / etc.) dominates the portfolio.
  asset,

  /// Holdings within one GICS-style sector are overweight.
  sector,

  /// Holdings in one market / region are overweight.
  region,

  /// Exposure denominated in a single currency is too high,
  /// creating FX-revaluation risk.
  currency,
}

/// Configurable thresholds for each [RiskDimension].
///
/// Each value is a weight in `[0, 1]`. Exceeding the threshold triggers a
/// [RiskSeverity.warning] alert; exceeding 1.5x the threshold (capped at 1.0)
/// triggers [RiskSeverity.critical].
class ConcentrationThresholds {
  const ConcentrationThresholds({
    required this.assetWarning,
    required this.sectorWarning,
    required this.regionWarning,
    required this.currencyWarning,
  });

  /// Product-spec defaults from the FIR-54 issue description.
  factory ConcentrationThresholds.defaults() => const ConcentrationThresholds(
    assetWarning: 0.20,
    sectorWarning: 0.35,
    regionWarning: 0.60,
    currencyWarning: 0.50,
  );

  /// Fraction of portfolio value above which a single asset is flagged.
  final double assetWarning;

  /// Fraction above which a sector bucket is flagged.
  final double sectorWarning;

  /// Fraction above which a region bucket is flagged.
  final double regionWarning;

  /// Fraction above which a single-currency exposure is flagged.
  final double currencyWarning;

  double forDimension(RiskDimension dim) => switch (dim) {
    RiskDimension.asset => assetWarning,
    RiskDimension.sector => sectorWarning,
    RiskDimension.region => regionWarning,
    RiskDimension.currency => currencyWarning,
  };

  ConcentrationThresholds copyWith({
    double? assetWarning,
    double? sectorWarning,
    double? regionWarning,
    double? currencyWarning,
  }) => ConcentrationThresholds(
    assetWarning: assetWarning ?? this.assetWarning,
    sectorWarning: sectorWarning ?? this.sectorWarning,
    regionWarning: regionWarning ?? this.regionWarning,
    currencyWarning: currencyWarning ?? this.currencyWarning,
  );
}

/// One concentration risk alert produced by [ConcentrationRiskService].
class ConcentrationAlert {
  const ConcentrationAlert({
    required this.dimension,
    required this.severity,
    required this.label,
    required this.weight,
    required this.threshold,
    required this.valueInBase,
    required this.assetIds,
  });

  final RiskDimension dimension;
  final RiskSeverity severity;

  /// Human-readable name of the offending bucket (e.g. "AAPL", "Technology").
  final String label;

  /// Portfolio weight of the concentrated position (0..1).
  final double weight;

  /// The threshold that was breached.
  final double threshold;

  /// Aggregate market value in base currency.
  final Decimal valueInBase;

  /// IDs of the assets contributing to this concentration.
  final List<String> assetIds;
}

/// Pure service: scan a portfolio snapshot and emit [ConcentrationAlert]s
/// for every dimension that exceeds its threshold.
class ConcentrationRiskService {
  const ConcentrationRiskService();

  /// Detect concentration alerts across all four dimensions.
  ///
  /// [snapshots] — the current portfolio (all asset types, not just equities).
  /// [assetLookup] — resolves an assetId to its [Asset] metadata.
  /// [classifier] — classifies equity assets by sector / region.
  /// [thresholds] — the user's configured alert thresholds.
  List<ConcentrationAlert> detect({
    required Iterable<HoldingSnapshot> snapshots,
    required Asset? Function(String assetId) assetLookup,
    required EquityClassifier classifier,
    required ConcentrationThresholds thresholds,
  }) {
    final alerts = <ConcentrationAlert>[];
    final holdings = <_ResolvedHolding>[];

    // 1. Resolve every snapshot into a full holding record.
    var totalValue = Decimal.zero;
    for (final s in snapshots) {
      if (s.marketValueInBase.sign <= 0) continue;
      final asset = assetLookup(s.assetId);
      if (asset == null) continue;
      totalValue += s.marketValueInBase;
      holdings.add(_ResolvedHolding(snapshot: s, asset: asset));
    }
    if (totalValue.sign == 0) return alerts;

    // 2. Per-asset concentration.
    _detectAssetConcentration(holdings, totalValue, thresholds, alerts);

    // 3. Sector concentration (equities only).
    _detectSectorConcentration(
      holdings,
      totalValue,
      classifier,
      thresholds,
      alerts,
    );

    // 4. Region concentration (equities only).
    _detectRegionConcentration(
      holdings,
      totalValue,
      classifier,
      thresholds,
      alerts,
    );

    // 5. Currency concentration (all assets).
    _detectCurrencyConcentration(holdings, totalValue, thresholds, alerts);

    // Sort: critical first, then by weight descending.
    alerts.sort((a, b) {
      final sev = a.severity.index.compareTo(b.severity.index);
      if (sev != 0) return sev;
      return b.weight.compareTo(a.weight);
    });

    return alerts;
  }

  void _detectAssetConcentration(
    List<_ResolvedHolding> holdings,
    Decimal totalValue,
    ConcentrationThresholds thresholds,
    List<ConcentrationAlert> alerts,
  ) {
    for (final h in holdings) {
      final weight = (h.snapshot.marketValueInBase / totalValue).toDouble();
      if (weight > thresholds.assetWarning) {
        alerts.add(
          ConcentrationAlert(
            dimension: RiskDimension.asset,
            severity: _severity(weight, thresholds.assetWarning),
            label: h.asset.name ?? h.asset.symbol,
            weight: weight,
            threshold: thresholds.assetWarning,
            valueInBase: h.snapshot.marketValueInBase,
            assetIds: [h.asset.id],
          ),
        );
      }
    }
  }

  void _detectSectorConcentration(
    List<_ResolvedHolding> holdings,
    Decimal totalValue,
    EquityClassifier classifier,
    ConcentrationThresholds thresholds,
    List<ConcentrationAlert> alerts,
  ) {
    final sectorAgg = <String, _SectorAggregate>{};
    for (final h in holdings) {
      if (!kEquityAssetTypes.contains(h.asset.type)) continue;
      final classification = classifier.classify(h.asset);
      if (classification.sector.isMissing) continue;
      final sector = classification.sector.value!;
      final agg = sectorAgg.putIfAbsent(
        sector,
        () => _SectorAggregate(sector: sector),
      );
      agg.totalValue += h.snapshot.marketValueInBase;
      agg.assetIds.add(h.asset.id);
    }

    for (final agg in sectorAgg.values) {
      final weight = (agg.totalValue / totalValue).toDouble();
      if (weight > thresholds.sectorWarning) {
        alerts.add(
          ConcentrationAlert(
            dimension: RiskDimension.sector,
            severity: _severity(weight, thresholds.sectorWarning),
            label: agg.sector,
            weight: weight,
            threshold: thresholds.sectorWarning,
            valueInBase: agg.totalValue,
            assetIds: agg.assetIds,
          ),
        );
      }
    }
  }

  void _detectRegionConcentration(
    List<_ResolvedHolding> holdings,
    Decimal totalValue,
    EquityClassifier classifier,
    ConcentrationThresholds thresholds,
    List<ConcentrationAlert> alerts,
  ) {
    final regionAgg = <String, _RegionAggregate>{};
    for (final h in holdings) {
      if (!kEquityAssetTypes.contains(h.asset.type)) continue;
      final classification = classifier.classify(h.asset);
      if (classification.region.isMissing) continue;
      final region = classification.region.value!.name;
      final agg = regionAgg.putIfAbsent(
        region,
        () => _RegionAggregate(region: region),
      );
      agg.totalValue += h.snapshot.marketValueInBase;
      agg.assetIds.add(h.asset.id);
    }

    for (final agg in regionAgg.values) {
      final weight = (agg.totalValue / totalValue).toDouble();
      if (weight > thresholds.regionWarning) {
        alerts.add(
          ConcentrationAlert(
            dimension: RiskDimension.region,
            severity: _severity(weight, thresholds.regionWarning),
            label: agg.region,
            weight: weight,
            threshold: thresholds.regionWarning,
            valueInBase: agg.totalValue,
            assetIds: agg.assetIds,
          ),
        );
      }
    }
  }

  void _detectCurrencyConcentration(
    List<_ResolvedHolding> holdings,
    Decimal totalValue,
    ConcentrationThresholds thresholds,
    List<ConcentrationAlert> alerts,
  ) {
    final currAgg = <String, _CurrencyAggregate>{};
    for (final h in holdings) {
      final currency = h.asset.currency;
      final agg = currAgg.putIfAbsent(
        currency,
        () => _CurrencyAggregate(currency: currency),
      );
      agg.totalValue += h.snapshot.marketValueInBase;
      agg.assetIds.add(h.asset.id);
    }

    for (final agg in currAgg.values) {
      final weight = (agg.totalValue / totalValue).toDouble();
      if (weight > thresholds.currencyWarning) {
        alerts.add(
          ConcentrationAlert(
            dimension: RiskDimension.currency,
            severity: _severity(weight, thresholds.currencyWarning),
            label: agg.currency,
            weight: weight,
            threshold: thresholds.currencyWarning,
            valueInBase: agg.totalValue,
            assetIds: agg.assetIds,
          ),
        );
      }
    }
  }

  /// 1.0x–1.5x threshold → warning; > 1.5x → critical.
  static RiskSeverity _severity(double weight, double threshold) {
    return weight > threshold * 1.5
        ? RiskSeverity.critical
        : RiskSeverity.warning;
  }
}

class _ResolvedHolding {
  const _ResolvedHolding({required this.snapshot, required this.asset});
  final HoldingSnapshot snapshot;
  final Asset asset;
}

class _SectorAggregate {
  _SectorAggregate({required this.sector});
  final String sector;
  Decimal totalValue = Decimal.zero;
  final List<String> assetIds = [];
}

class _RegionAggregate {
  _RegionAggregate({required this.region});
  final String region;
  Decimal totalValue = Decimal.zero;
  final List<String> assetIds = [];
}

class _CurrencyAggregate {
  _CurrencyAggregate({required this.currency});
  final String currency;
  Decimal totalValue = Decimal.zero;
  final List<String> assetIds = [];
}
