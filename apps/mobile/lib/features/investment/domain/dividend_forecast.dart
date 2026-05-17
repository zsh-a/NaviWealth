import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'models/cash_dividend.dart';
import 'models/corporate_actions.dart';
import 'models/holding_snapshot.dart';

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

class TrailingTwelveMonthsStrategy implements DividendForecastStrategy {
  const TrailingTwelveMonthsStrategy();

  @override
  String get name => 'ttm';

  @override
  DividendForecastConfidence get confidence => DividendForecastConfidence.low;

  @override
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
        strategy: name,
        confidence: confidence,
      );
    }

    final forecastStart = _addMonths(_utcDay(horizonEnd), -12);
    final trailingStart = _addMonths(forecastStart, -12);
    final assets = holdingList.map((h) => h.assetId).toSet();
    final schedule = <DateTime, Decimal>{};

    for (final dividend in history) {
      final date = dividend.effectiveDate.toUtc();
      if (!assets.contains(dividend.assetId)) continue;
      if (date.isBefore(trailingStart) || date.isAfter(forecastStart)) {
        continue;
      }
      _addToSchedule(
        schedule,
        _utcDay(_addMonths(dividend.effectiveDate, 12)),
        dividend.grossAmount,
      );
    }

    return _result(
      assetId: _assetIdFor(holdingList),
      schedule: schedule,
      currency: currency,
      strategy: name,
      confidence: confidence,
    );
  }
}

class DeclaredActionsStrategy implements DividendForecastStrategy {
  const DeclaredActionsStrategy();

  @override
  String get name => 'declared';

  @override
  DividendForecastConfidence get confidence => DividendForecastConfidence.high;

  @override
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
        strategy: name,
        confidence: confidence,
      );
    }

    final forecastStart = _addMonths(_utcDay(horizonEnd), -12);
    final holdingsByAsset = {for (final h in holdingList) h.assetId: h};
    final schedule = <DateTime, Decimal>{};

    for (final action in declared) {
      final date = action.effectiveDate.toUtc();
      if (!date.isAfter(forecastStart) || date.isAfter(horizonEnd)) continue;
      final holding = holdingsByAsset[action.assetId];
      if (holding == null || !_hasOpenQuantity(holding)) continue;
      final amountPerShare = switch (action) {
        CashDividendAction a => a.amountPerShare,
        DripAction a => a.amountPerShare,
        _ => null,
      };
      if (amountPerShare == null) continue;
      _addToSchedule(
        schedule,
        _utcDay(action.effectiveDate),
        amountPerShare * holding.quantity,
      );
    }

    return _result(
      assetId: _assetIdFor(holdingList),
      schedule: schedule,
      currency: currency,
      strategy: name,
      confidence: confidence,
    );
  }
}

class DpsExtrapolationStrategy implements DividendForecastStrategy {
  const DpsExtrapolationStrategy();

  @override
  String get name => 'dps';

  @override
  DividendForecastConfidence get confidence =>
      DividendForecastConfidence.medium;

  @override
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
        strategy: name,
        confidence: confidence,
      );
    }

    final forecastStart = _addMonths(_utcDay(horizonEnd), -12);
    final trailingStart = _addMonths(forecastStart, -12);
    final historyByAsset = <String, List<CashDividend>>{};
    for (final dividend in history) {
      final date = dividend.effectiveDate.toUtc();
      if (date.isBefore(trailingStart) || date.isAfter(forecastStart)) {
        continue;
      }
      historyByAsset
          .putIfAbsent(dividend.assetId, () => <CashDividend>[])
          .add(dividend);
    }

    final schedule = <DateTime, Decimal>{};
    for (final holding in holdingList) {
      final assetHistory = historyByAsset[holding.assetId];
      if (assetHistory == null || assetHistory.isEmpty) continue;
      assetHistory.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
      final frequency = _estimatedAnnualFrequency(assetHistory);
      final averageDps =
          (assetHistory.fold<Decimal>(
                    Decimal.zero,
                    (total, dividend) => total + dividend.amountPerShare,
                  ) /
                  Decimal.fromInt(assetHistory.length))
              .toDecimal(scaleOnInfinitePrecision: 8);
      final annualAmount =
          averageDps * Decimal.fromInt(frequency) * holding.quantity;
      if (annualAmount <= Decimal.zero) continue;

      final amountPerPayment = (annualAmount / Decimal.fromInt(frequency))
          .toDecimal(scaleOnInfinitePrecision: 8);
      final intervalMonths = (12 / frequency).round();
      for (var i = 1; i <= frequency; i++) {
        final projectedDate = _addMonths(forecastStart, i * intervalMonths);
        if (projectedDate.isAfter(horizonEnd)) continue;
        _addToSchedule(schedule, _utcDay(projectedDate), amountPerPayment);
      }
    }

    return _result(
      assetId: _assetIdFor(holdingList),
      schedule: schedule,
      currency: currency,
      strategy: name,
      confidence: confidence,
    );
  }
}

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

    for (final holding in holdingList) {
      final assetHistory = history.where((d) => d.assetId == holding.assetId);
      final assetDeclared = declared.where((a) => a.assetId == holding.assetId);
      final single = [holding];
      final chosen = _firstUsable([
        declaredStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        ),
        dpsStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        ),
        ttmStrategy.forecast(
          holdings: single,
          history: assetHistory,
          declared: assetDeclared,
          horizonEnd: horizonEnd,
        ),
      ]);
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

  ProjectedDividend? _firstUsable(List<ProjectedDividend> candidates) {
    for (final candidate in candidates) {
      if (candidate.total > Decimal.zero) return candidate;
    }
    return null;
  }
}

const _portfolioAssetId = 'portfolio';

ProjectedDividend _result({
  required String assetId,
  required Map<DateTime, Decimal> schedule,
  required String currency,
  required String strategy,
  required DividendForecastConfidence confidence,
}) {
  return ProjectedDividend(
    assetId: assetId,
    perAsset: Map.unmodifiable(schedule),
    total: _sum(schedule.values),
    currency: currency,
    strategy: strategy,
    confidence: confidence,
    strategyBreakdown: schedule.isEmpty
        ? const <String, Decimal>{}
        : Map.unmodifiable({strategy: _sum(schedule.values)}),
  );
}

bool _hasOpenQuantity(HoldingSnapshot holding) =>
    holding.quantity > Decimal.zero;

String _assetIdFor(List<HoldingSnapshot> holdings) =>
    holdings.length == 1 ? holdings.single.assetId : _portfolioAssetId;

String _forecastCurrency(
  Iterable<HoldingSnapshot> holdings,
  Iterable<CashDividend> history,
  Iterable<CorporateAction> declared,
) {
  final holding = holdings.firstOrNull;
  if (holding != null) return holding.baseCurrency;
  final dividend = history.firstOrNull;
  if (dividend != null) return dividend.currency;
  for (final action in declared) {
    switch (action) {
      case CashDividendAction a:
        return a.currency;
      case DripAction a:
        return a.currency;
      default:
        continue;
    }
  }
  return '';
}

int _estimatedAnnualFrequency(List<CashDividend> history) {
  if (history.length <= 1) return 1;
  var totalGapDays = 0;
  var gaps = 0;
  for (var i = 1; i < history.length; i++) {
    final gap = history[i].effectiveDate
        .toUtc()
        .difference(history[i - 1].effectiveDate.toUtc())
        .inDays
        .abs();
    if (gap == 0) continue;
    totalGapDays += gap;
    gaps++;
  }
  if (gaps == 0) return 1;
  final averageGap = totalGapDays / gaps;
  if (averageGap <= 45) return 12;
  if (averageGap <= 100) return 4;
  if (averageGap <= 200) return 2;
  return 1;
}

DividendForecastConfidence _lowestConfidence(
  DividendForecastConfidence a,
  DividendForecastConfidence b,
) {
  return a.index >= b.index ? a : b;
}

void _addToSchedule(
  Map<DateTime, Decimal> schedule,
  DateTime date,
  Decimal amount,
) {
  if (amount <= Decimal.zero) return;
  final key = _utcDay(date);
  schedule[key] = (schedule[key] ?? Decimal.zero) + amount;
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}

DateTime _utcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _addMonths(DateTime date, int delta) {
  final utc = date.toUtc();
  final monthIndex = utc.year * 12 + utc.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = utc.day > lastDay ? lastDay : utc.day;
  return DateTime.utc(
    year,
    month,
    day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}
