part of 'dividend_forecast.dart';

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
      final actionCurrency = switch (action) {
        CashDividendAction a => a.currency,
        DripAction a => a.currency,
        _ => null,
      };
      if (actionCurrency == null ||
          actionCurrency.toUpperCase() != holding.baseCurrency.toUpperCase()) {
        continue;
      }
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
