part of 'dividend_forecast.dart';

enum DividendForecastConfidence { high, medium, low }

abstract class DividendForecastStrategy {
  String get name;

  DividendForecastConfidence get confidence;

  ProjectedDividend forecast({
    required Iterable<HoldingSnapshot> holdings,
    required Iterable<CashDividend> history,
    required Iterable<CorporateAction> declared,
    required DateTime horizonEnd,
  });
}

@immutable
class ProjectedDividend {
  const ProjectedDividend({
    required this.assetId,
    required this.perAsset,
    required this.total,
    required this.currency,
    required this.strategy,
    required this.confidence,
    this.strategyBreakdown = const <String, Decimal>{},
    this.assetStrategies = const <String, String>{},
    this.excludedDeclaredCurrencies = const <String>{},
  });

  final String assetId;

  /// Forecast schedule keyed by UTC day. The issue contract names this field
  /// `perAsset`; callers use it as the per-date forecast distribution.
  final Map<DateTime, Decimal> perAsset;
  final Decimal total;
  final String currency;
  final String strategy;
  final DividendForecastConfidence confidence;
  final Map<String, Decimal> strategyBreakdown;
  final Map<String, String> assetStrategies;
  final Set<String> excludedDeclaredCurrencies;

  ProjectedDividend withExcludedDeclaredCurrencies(Set<String> currencies) {
    return ProjectedDividend(
      assetId: assetId,
      perAsset: perAsset,
      total: total,
      currency: currency,
      strategy: strategy,
      confidence: confidence,
      strategyBreakdown: strategyBreakdown,
      assetStrategies: assetStrategies,
      excludedDeclaredCurrencies: Set.unmodifiable(currencies),
    );
  }

  Decimal amountInMonth(DateTime month) {
    final start = DateTime.utc(month.year, month.month);
    final end = _addMonths(start, 1);
    return perAsset.entries.fold(Decimal.zero, (total, entry) {
      final date = entry.key.toUtc();
      if (date.isBefore(start) || !date.isBefore(end)) return total;
      return total + entry.value;
    });
  }

  static ProjectedDividend empty({
    required String assetId,
    required String currency,
    required String strategy,
    required DividendForecastConfidence confidence,
  }) {
    return ProjectedDividend(
      assetId: assetId,
      perAsset: const <DateTime, Decimal>{},
      total: Decimal.zero,
      currency: currency,
      strategy: strategy,
      confidence: confidence,
    );
  }
}
