import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'models/cash_dividend.dart';
import 'models/corporate_actions.dart';
import 'models/holding_snapshot.dart';

part 'dividend_forecast_helpers.dart';
part 'dividend_forecast_models.dart';
part 'dividend_forecast_strategies.dart';

class DividendForecastService {
  const DividendForecastService({
    this.declaredStrategy = const DeclaredActionsStrategy(),
    this.dpsStrategy = const DpsExtrapolationStrategy(),
    this.ttmStrategy = const TrailingTwelveMonthsStrategy(),
  });

  final DividendForecastStrategy declaredStrategy;
  final DividendForecastStrategy dpsStrategy;
  final DividendForecastStrategy ttmStrategy;

  ProjectedDividend forecast({
    required Iterable<HoldingSnapshot> holdings,
    required Iterable<CashDividend> history,
    required Iterable<CorporateAction> declared,
    required DateTime horizonEnd,
  }) {
    final holdingList = holdings.where(_hasOpenQuantity).toList();
    final currency = _forecastCurrency(holdingList, history, declared);
    if (holdingList.isEmpty) {
      return ProjectedDividend.empty(
        assetId: _portfolioAssetId,
        currency: currency,
        strategy: 'composite',
        confidence: DividendForecastConfidence.low,
      );
    }

    final schedule = <DateTime, Decimal>{};
    final breakdown = <String, Decimal>{};
    final assetStrategies = <String, String>{};
    var confidence = DividendForecastConfidence.high;
    final holdingAssetIds = {
      for (final holding in holdingList) holding.assetId,
    };
    final historyByAsset = <String, List<CashDividend>>{};
    for (final dividend in history) {
      if (!holdingAssetIds.contains(dividend.assetId)) continue;
      historyByAsset
          .putIfAbsent(dividend.assetId, () => <CashDividend>[])
          .add(dividend);
    }
    final declaredByAsset = <String, List<CorporateAction>>{};
    for (final action in declared) {
      if (!holdingAssetIds.contains(action.assetId)) continue;
      declaredByAsset
          .putIfAbsent(action.assetId, () => <CorporateAction>[])
          .add(action);
    }

    for (final holding in holdingList) {
      final assetHistory =
          historyByAsset[holding.assetId] ?? const <CashDividend>[];
      final assetDeclared =
          declaredByAsset[holding.assetId] ?? const <CorporateAction>[];
      final single = [holding];
      final chosen = _firstUsable(() sync* {
        yield declaredStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        );
        yield dpsStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        );
        yield ttmStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        );
      }());
      if (chosen == null) continue;
      for (final entry in chosen.perAsset.entries) {
        _addToSchedule(schedule, entry.key, entry.value);
      }
      breakdown[chosen.strategy] =
          (breakdown[chosen.strategy] ?? Decimal.zero) + chosen.total;
      assetStrategies[holding.assetId] = chosen.strategy;
      confidence = _lowestConfidence(confidence, chosen.confidence);
    }

    return ProjectedDividend(
      assetId: _portfolioAssetId,
      perAsset: Map.unmodifiable(schedule),
      total: _sum(schedule.values),
      currency: currency,
      strategy: 'composite',
      confidence: assetStrategies.isEmpty
          ? DividendForecastConfidence.low
          : confidence,
      strategyBreakdown: Map.unmodifiable(breakdown),
      assetStrategies: Map.unmodifiable(assetStrategies),
    );
  }

  ProjectedDividend? _firstUsable(Iterable<ProjectedDividend> candidates) {
    for (final candidate in candidates) {
      if (candidate.total > Decimal.zero) return candidate;
    }
    return null;
  }
}
