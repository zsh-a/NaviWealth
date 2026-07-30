import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import '../domain/holding_service.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/portfolio_trend.dart';

class PortfolioTrendService {
  const PortfolioTrendService({
    required this.holdings,
    required this.converter,
    required this.baseCurrency,
  });

  final HoldingService holdings;
  final CurrencyConverter converter;
  final String baseCurrency;

  Future<Map<String, PortfolioTrendSeries>> computeMany({
    required Iterable<InvestmentPortfolio> portfolios,
    required List<PortfolioCapitalAssignment> assignmentHistory,
    required PortfolioTrendRange range,
    DateTime? now,
  }) async {
    final portfolioList = portfolios.toList(growable: false);
    if (portfolioList.isEmpty) return const {};

    final end = (now ?? DateTime.now()).toUtc();
    final datesByPortfolio = <String, List<DateTime>>{
      for (final portfolio in portfolioList)
        portfolio.id: _sampleDates(
          createdAt: portfolio.createdAt,
          end: end,
          range: range,
        ),
    };
    final allDates = datesByPortfolio.values.expand((dates) => dates).toSet();
    final samples = await holdings.computeAtSamples(allDates);
    final sampleByInstant = {for (final sample in samples) sample.asOf: sample};

    return {
      for (final portfolio in portfolioList)
        portfolio.id: _buildSeries(
          portfolio: portfolio,
          range: range,
          dates: datesByPortfolio[portfolio.id]!,
          sampleByInstant: sampleByInstant,
          assignmentHistory: assignmentHistory,
        ),
    };
  }

  PortfolioTrendSeries _buildSeries({
    required InvestmentPortfolio portfolio,
    required PortfolioTrendRange range,
    required List<DateTime> dates,
    required Map<DateTime, HoldingSample> sampleByInstant,
    required List<PortfolioCapitalAssignment> assignmentHistory,
  }) {
    final history = assignmentHistory
        .where((assignment) => assignment.portfolioId == portfolio.id)
        .toList(growable: false);
    final points = <PortfolioTrendPoint>[];
    DateTime? previousAt;
    Decimal? previousValue;
    var cumulativeGrowth = 1.0;

    for (final date in dates) {
      final sample =
          sampleByInstant[date] ??
          HoldingSample(asOf: date, snapshots: const {});
      final valuation = _valueAt(
        sample: sample,
        assignments: history.where((item) => item.isActiveAt(date)),
      );
      final flow = previousAt == null
          ? Decimal.zero
          : _boundaryFlow(
              portfolioId: portfolio.id,
              fromExclusive: previousAt,
              toInclusive: date,
              sample: sample,
              history: assignmentHistory,
            );

      final prior = previousValue;
      if (prior != null && prior > Decimal.zero) {
        final numerator = valuation.marketValue - flow;
        final subperiod = (numerator / prior).toDouble() - 1;
        if (subperiod.isFinite && subperiod > -1) {
          cumulativeGrowth *= 1 + subperiod;
        }
      }

      points.add(
        PortfolioTrendPoint(
          asOf: date,
          marketValueInBase: valuation.marketValue,
          costBasisInBase: valuation.costBasis,
          cashValueInBase: valuation.cashValue,
          netFlowInBase: flow,
          performanceRatio: cumulativeGrowth - 1,
          quality: valuation.estimated
              ? PortfolioTrendQuality.estimated
              : PortfolioTrendQuality.complete,
        ),
      );
      previousAt = date;
      previousValue = valuation.marketValue;
    }

    return PortfolioTrendSeries(
      portfolioId: portfolio.id,
      baseCurrency: baseCurrency,
      range: range,
      points: List.unmodifiable(points),
    );
  }

  _PortfolioValuation _valueAt({
    required HoldingSample sample,
    required Iterable<PortfolioCapitalAssignment> assignments,
  }) {
    final active = assignments.toList(growable: false);
    final lotsById = {for (final lot in sample.lots) lot.id: lot};
    final totalQuantityByAsset = <String, Decimal>{};
    final totalCostByAsset = <String, Decimal>{};
    for (final lot in sample.lots.where((lot) => !lot.isClosed)) {
      totalQuantityByAsset.update(
        lot.assetId,
        (value) => value + lot.remainingQuantity,
        ifAbsent: () => lot.remainingQuantity,
      );
      totalCostByAsset.update(
        lot.assetId,
        (value) => value + lot.remainingCost,
        ifAbsent: () => lot.remainingCost,
      );
    }

    final selectedQuantityByAsset = <String, Decimal>{};
    final selectedCostByAsset = <String, Decimal>{};
    final selectedAssetIds = <String>{};
    var cashValue = Decimal.zero;
    var estimated = false;

    for (final assignment in active) {
      switch (assignment.sourceKind) {
        case PortfolioCapitalSourceKind.lot:
          final lot = lotsById[assignment.sourceId];
          if (lot == null || lot.isClosed) continue;
          final requested = assignment.quantity ?? lot.remainingQuantity;
          final quantity = requested > lot.remainingQuantity
              ? lot.remainingQuantity
              : requested;
          if (quantity <= Decimal.zero) continue;
          selectedAssetIds.add(lot.assetId);
          selectedQuantityByAsset.update(
            lot.assetId,
            (value) => value + quantity,
            ifAbsent: () => quantity,
          );
          final cost = quantity * lot.costPerUnit;
          selectedCostByAsset.update(
            lot.assetId,
            (value) => value + cost,
            ifAbsent: () => cost,
          );
        case PortfolioCapitalSourceKind.cashAccount:
          try {
            cashValue += converter
                .convert(
                  Money(assignment.amount!, assignment.currency!),
                  baseCurrency,
                  on: sample.asOf,
                )
                .amount;
          } on FxRateNotFoundError {
            estimated = true;
          }
      }
    }

    var securitiesValue = Decimal.zero;
    var securitiesCost = Decimal.zero;
    for (final entry in selectedQuantityByAsset.entries) {
      final snapshot = sample.snapshots[entry.key];
      final totalQuantity = totalQuantityByAsset[entry.key] ?? Decimal.zero;
      if (snapshot == null || totalQuantity <= Decimal.zero) {
        estimated = true;
        continue;
      }
      final ratio = (entry.value / totalQuantity).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      securitiesValue += snapshot.marketValueInBase * ratio;

      final totalCost = totalCostByAsset[entry.key] ?? Decimal.zero;
      final selectedCost = selectedCostByAsset[entry.key] ?? Decimal.zero;
      final costRatio = totalCost <= Decimal.zero
          ? ratio
          : (selectedCost / totalCost).toDecimal(scaleOnInfinitePrecision: 12);
      securitiesCost += snapshot.costBasisInBase * costRatio;
    }

    if (sample.issues.any(
      (issue) => selectedAssetIds.contains(issue.assetId),
    )) {
      estimated = true;
    }

    return _PortfolioValuation(
      marketValue: securitiesValue + cashValue,
      costBasis: securitiesCost + cashValue,
      cashValue: cashValue,
      estimated: estimated,
    );
  }

  Decimal _boundaryFlow({
    required String portfolioId,
    required DateTime fromExclusive,
    required DateTime toInclusive,
    required HoldingSample sample,
    required List<PortfolioCapitalAssignment> history,
  }) {
    var result = Decimal.zero;
    for (final assignment in history) {
      if (assignment.portfolioId != portfolioId) continue;
      if (_inside(
        assignment.assignedAt,
        fromExclusive: fromExclusive,
        toInclusive: toInclusive,
      )) {
        result += _assignmentValueAt(assignment, sample);
      }
      final unassignedAt = assignment.unassignedAt;
      if (unassignedAt != null &&
          _inside(
            unassignedAt,
            fromExclusive: fromExclusive,
            toInclusive: toInclusive,
          )) {
        result -= _assignmentValueAt(assignment, sample);
      }
    }
    return result;
  }

  Decimal _assignmentValueAt(
    PortfolioCapitalAssignment assignment,
    HoldingSample sample,
  ) {
    switch (assignment.sourceKind) {
      case PortfolioCapitalSourceKind.cashAccount:
        try {
          return converter
              .convert(
                Money(assignment.amount!, assignment.currency!),
                baseCurrency,
                on: sample.asOf,
              )
              .amount;
        } on FxRateNotFoundError {
          return Decimal.zero;
        }
      case PortfolioCapitalSourceKind.lot:
        final lot = sample.lots
            .where((candidate) => candidate.id == assignment.sourceId)
            .firstOrNull;
        if (lot == null || lot.remainingQuantity <= Decimal.zero) {
          return Decimal.zero;
        }
        final snapshot = sample.snapshots[lot.assetId];
        if (snapshot == null || snapshot.quantity <= Decimal.zero) {
          return Decimal.zero;
        }
        final quantity = assignment.quantity == null
            ? lot.remainingQuantity
            : _minDecimal(assignment.quantity!, lot.remainingQuantity);
        return snapshot.marketValueInBase *
            (quantity / snapshot.quantity).toDecimal(
              scaleOnInfinitePrecision: 12,
            );
    }
  }

  static List<DateTime> _sampleDates({
    required DateTime createdAt,
    required DateTime end,
    required PortfolioTrendRange range,
  }) {
    final utcEnd = end.toUtc();
    final requestedStart = switch (range) {
      PortfolioTrendRange.month => utcEnd.subtract(const Duration(days: 30)),
      PortfolioTrendRange.quarter => utcEnd.subtract(const Duration(days: 90)),
      PortfolioTrendRange.yearToDate => DateTime.utc(utcEnd.year),
      PortfolioTrendRange.year => utcEnd.subtract(const Duration(days: 365)),
      PortfolioTrendRange.all => createdAt.toUtc(),
    };
    final start = requestedStart.isAfter(createdAt.toUtc())
        ? requestedStart
        : createdAt.toUtc();
    if (!start.isBefore(utcEnd)) return [utcEnd];

    final spanDays = math.max(1, utcEnd.difference(start).inDays);
    final cadenceDays = math.max(1, (spanDays / 120).ceil());
    final dates = <DateTime>[];
    var cursor = _endOfUtcDay(start);
    while (cursor.isBefore(utcEnd)) {
      dates.add(cursor);
      cursor = cursor.add(Duration(days: cadenceDays));
    }
    if (dates.isEmpty || dates.last != utcEnd) dates.add(utcEnd);
    return dates;
  }

  static DateTime _endOfUtcDay(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, 23, 59, 59, 999, 999);
  }

  static bool _inside(
    DateTime instant, {
    required DateTime fromExclusive,
    required DateTime toInclusive,
  }) {
    final value = instant.toUtc();
    return value.isAfter(fromExclusive.toUtc()) &&
        !value.isAfter(toInclusive.toUtc());
  }
}

class _PortfolioValuation {
  const _PortfolioValuation({
    required this.marketValue,
    required this.costBasis,
    required this.cashValue,
    required this.estimated,
  });

  final Decimal marketValue;
  final Decimal costBasis;
  final Decimal cashValue;
  final bool estimated;
}

Decimal _minDecimal(Decimal a, Decimal b) => a < b ? a : b;
