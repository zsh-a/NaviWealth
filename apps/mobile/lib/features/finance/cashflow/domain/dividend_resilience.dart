import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

import 'dividend_center.dart';

enum DividendResilienceConfidence { low, medium, high }

enum DividendChangeDriver { holdingQuantity, unitDividend, fx, localCombined }

@immutable
class RollingDividendPoint {
  const RollingDividendPoint({
    required this.asOf,
    required this.gross,
    required this.net,
    required this.hasFullWindow,
  });

  final DateTime asOf;
  final Decimal gross;
  final Decimal net;
  final bool hasFullWindow;
}

@immutable
class DividendIncomeDrawdown {
  const DividendIncomeDrawdown({
    required this.ratio,
    required this.peakAt,
    required this.troughAt,
    this.recoveredAt,
  });

  final double ratio;
  final DateTime peakAt;
  final DateTime troughAt;
  final DateTime? recoveredAt;

  int? get recoveryMonths =>
      recoveredAt == null ? null : _monthDistance(troughAt, recoveredAt!);
}

@immutable
class DividendChangeAttribution {
  const DividendChangeAttribution({
    required this.assetId,
    required this.assetLabel,
    required this.currentGross,
    required this.priorGross,
    required this.holdingQuantityImpact,
    required this.unitDividendImpact,
    required this.fxImpact,
    required this.localCombinedImpact,
    required this.matchedUnitDividend,
  });

  final String assetId;
  final String assetLabel;
  final Decimal currentGross;
  final Decimal priorGross;
  final Decimal holdingQuantityImpact;
  final Decimal unitDividendImpact;
  final Decimal fxImpact;
  final Decimal localCombinedImpact;
  final bool matchedUnitDividend;

  Decimal get totalChange => currentGross - priorGross;

  DividendChangeDriver get primaryDriver {
    final candidates = <DividendChangeDriver, Decimal>{
      if (matchedUnitDividend) ...{
        DividendChangeDriver.holdingQuantity: holdingQuantityImpact.abs(),
        DividendChangeDriver.unitDividend: unitDividendImpact.abs(),
      } else
        DividendChangeDriver.localCombined: localCombinedImpact.abs(),
      DividendChangeDriver.fx: fxImpact.abs(),
    };
    return candidates.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

@immutable
class DividendResilienceReport {
  const DividendResilienceReport({
    required this.periodStart,
    required this.periodEnd,
    required this.observedMonthCount,
    required this.monthsWithoutRecordedDividends,
    required this.rolling,
    required this.netIncomeCagr,
    required this.maxDrawdown,
    required this.largestSourceLabel,
    required this.largestSourceShare,
    required this.sourceConcentration,
    required this.netRetentionRatio,
    required this.confidence,
    required this.attributions,
    required this.unitDividendMatchRatio,
    required this.excludedEventCount,
  });

  final DateTime? periodStart;
  final DateTime periodEnd;
  final int observedMonthCount;
  final int monthsWithoutRecordedDividends;
  final List<RollingDividendPoint> rolling;
  final double? netIncomeCagr;
  final DividendIncomeDrawdown? maxDrawdown;
  final String? largestSourceLabel;
  final double? largestSourceShare;

  /// Herfindahl concentration index over the latest complete rolling window.
  final double? sourceConcentration;
  final double? netRetentionRatio;
  final DividendResilienceConfidence confidence;
  final List<DividendChangeAttribution> attributions;
  final double unitDividendMatchRatio;
  final int excludedEventCount;

  bool get hasFullHistory => rolling.any((point) => point.hasFullWindow);
}

/// Historical resilience review over the user's recorded dividend ledger.
///
/// This is deliberately not a security-selection backtest. Metrics use only
/// recorded cash flows. Per-share corporate actions are optional evidence used
/// to separate holding-quantity changes from unit-dividend changes; otherwise
/// the report keeps those effects combined instead of inventing precision.
class DividendResilienceService {
  const DividendResilienceService();

  DividendResilienceReport analyze({
    required Iterable<DividendCenterEvent> events,
    required DateTime now,
    Iterable<CorporateAction> corporateActions = const [],
    int excludedEventCount = 0,
  }) {
    final nowUtc = now.toUtc();
    final rows =
        events
            .where((event) => !event.event.date.toUtc().isAfter(nowUtc))
            .toList()
          ..sort((a, b) => a.event.date.compareTo(b.event.date));
    final actions = <String, CorporateAction>{
      for (final action in corporateActions)
        if (action is CashDividendAction || action is DripAction)
          _actionKey(action.assetId, _transactionId(action)): action,
    };

    final earliest = rows.isEmpty ? null : rows.first.event.date.toUtc();
    final periodStart = earliest == null ? null : _month(earliest);
    final periodEnd = _month(nowUtc);
    final observedMonths = periodStart == null
        ? 0
        : _monthDistance(periodStart, periodEnd) + 1;
    final activeMonths = {
      for (final row in rows) _month(row.event.date.toUtc()),
    };
    final missingMonths = math.max(0, observedMonths - activeMonths.length);
    final rolling = _rolling(rows, periodStart: periodStart, now: nowUtc);
    final full = rolling.where((point) => point.hasFullWindow).toList();
    final latestWindowEnd = _month(nowUtc);
    final latestWindowStart = _addMonths(latestWindowEnd, -12);
    final latestRows = _inWindow(rows, latestWindowStart, latestWindowEnd);
    final concentration = _concentration(latestRows);
    final retention = _retention(latestRows);
    final attributions = _attribute(
      rows,
      actions: actions,
      currentStart: latestWindowStart,
      currentEnd: latestWindowEnd,
    );
    final matchRatio = _unitDividendMatchRatio(rows, actions);
    final confidence = _confidence(
      observedMonths: observedMonths,
      excludedEventCount: excludedEventCount,
      attributedRows: rows.where((row) => row.assetId != 'unattributed').length,
      totalRows: rows.length,
      unitDividendMatchRatio: matchRatio,
    );

    return DividendResilienceReport(
      periodStart: periodStart,
      periodEnd: periodEnd,
      observedMonthCount: observedMonths,
      monthsWithoutRecordedDividends: missingMonths,
      rolling: List.unmodifiable(rolling),
      netIncomeCagr: _cagr(full),
      maxDrawdown: _drawdown(full),
      largestSourceLabel: concentration?.label,
      largestSourceShare: concentration?.share,
      sourceConcentration: concentration?.hhi,
      netRetentionRatio: retention,
      confidence: confidence,
      attributions: List.unmodifiable(attributions),
      unitDividendMatchRatio: matchRatio,
      excludedEventCount: excludedEventCount,
    );
  }
}

List<RollingDividendPoint> _rolling(
  List<DividendCenterEvent> rows, {
  required DateTime? periodStart,
  required DateTime now,
}) {
  if (periodStart == null) return const [];
  final currentMonth = _month(now);
  final firstFullEnd = _addMonths(periodStart, 12);
  if (firstFullEnd.isAfter(currentMonth)) {
    final partial = _inWindow(rows, periodStart, currentMonth);
    return [
      RollingDividendPoint(
        asOf: currentMonth,
        gross: _gross(partial),
        net: _net(partial),
        hasFullWindow: false,
      ),
    ];
  }
  final result = <RollingDividendPoint>[];
  for (
    var end = firstFullEnd;
    !end.isAfter(currentMonth);
    end = _addMonths(end, 1)
  ) {
    final window = _inWindow(rows, _addMonths(end, -12), end);
    result.add(
      RollingDividendPoint(
        asOf: end,
        gross: _gross(window),
        net: _net(window),
        hasFullWindow: true,
      ),
    );
  }
  return result;
}

double? _cagr(List<RollingDividendPoint> points) {
  if (points.length < 13) return null;
  final first = points.first;
  final last = points.last;
  if (first.net <= Decimal.zero || last.net <= Decimal.zero) return null;
  final years = _monthDistance(first.asOf, last.asOf) / 12;
  if (years < 1) return null;
  final ratio = last.net.toDouble() / first.net.toDouble();
  final result = math.pow(ratio, 1 / years).toDouble() - 1;
  return result.isFinite ? result : null;
}

DividendIncomeDrawdown? _drawdown(List<RollingDividendPoint> points) {
  if (points.length < 2) return null;
  var peak = points.first;
  var worstRatio = 0.0;
  var worstPeak = peak;
  var trough = peak;
  for (final point in points.skip(1)) {
    if (point.net > peak.net) peak = point;
    if (peak.net <= Decimal.zero) continue;
    final ratio = ((peak.net - point.net) / peak.net)
        .toDecimal(scaleOnInfinitePrecision: 8)
        .toDouble();
    if (ratio > worstRatio) {
      worstRatio = ratio;
      worstPeak = peak;
      trough = point;
    }
  }
  if (worstRatio <= 0) return null;
  DateTime? recoveredAt;
  for (final point in points) {
    if (point.asOf.isAfter(trough.asOf) && point.net >= worstPeak.net) {
      recoveredAt = point.asOf;
      break;
    }
  }
  return DividendIncomeDrawdown(
    ratio: worstRatio,
    peakAt: worstPeak.asOf,
    troughAt: trough.asOf,
    recoveredAt: recoveredAt,
  );
}

({String label, double share, double hhi})? _concentration(
  List<DividendCenterEvent> rows,
) {
  final totals = <String, ({String label, Decimal amount})>{};
  for (final row in rows) {
    final previous = totals[row.assetId];
    totals[row.assetId] = (
      label: row.assetLabel,
      amount: (previous?.amount ?? Decimal.zero) + row.grossInBase,
    );
  }
  final total = totals.values.fold<Decimal>(
    Decimal.zero,
    (sum, item) => sum + item.amount,
  );
  if (total <= Decimal.zero) return null;
  String? label;
  var largest = 0.0;
  var hhi = 0.0;
  for (final item in totals.values) {
    final share = (item.amount / total)
        .toDecimal(scaleOnInfinitePrecision: 8)
        .toDouble();
    hhi += share * share;
    if (share > largest) {
      largest = share;
      label = item.label;
    }
  }
  return (label: label!, share: largest, hhi: hhi);
}

double? _retention(List<DividendCenterEvent> rows) {
  final gross = _gross(rows);
  if (gross <= Decimal.zero) return null;
  return (_net(rows) / gross).toDecimal(scaleOnInfinitePrecision: 8).toDouble();
}

List<DividendChangeAttribution> _attribute(
  List<DividendCenterEvent> rows, {
  required Map<String, CorporateAction> actions,
  required DateTime currentStart,
  required DateTime currentEnd,
}) {
  final priorStart = _addMonths(currentStart, -12);
  final current = _groupByAsset(_inWindow(rows, currentStart, currentEnd));
  final prior = _groupByAsset(_inWindow(rows, priorStart, currentStart));
  final ids = {...current.keys, ...prior.keys};
  final result = <DividendChangeAttribution>[];
  for (final id in ids) {
    if (id == 'unattributed') continue;
    final currentRows = current[id] ?? const <DividendCenterEvent>[];
    final priorRows = prior[id] ?? const <DividendCenterEvent>[];
    final currentGross = _gross(currentRows);
    final priorGross = _gross(priorRows);
    final currentOriginal = _originalGross(currentRows);
    final priorOriginal = _originalGross(priorRows);
    final comparableCurrency = _singleCurrency([...currentRows, ...priorRows]);
    var fxImpact = Decimal.zero;
    var localImpact = currentGross - priorGross;
    var holdingImpact = Decimal.zero;
    var unitImpact = Decimal.zero;
    var matched = false;
    if (comparableCurrency &&
        currentOriginal > Decimal.zero &&
        priorOriginal > Decimal.zero) {
      final currentRate = (currentGross / currentOriginal).toDecimal(
        scaleOnInfinitePrecision: 16,
      );
      final priorRate = (priorGross / priorOriginal).toDecimal(
        scaleOnInfinitePrecision: 16,
      );
      fxImpact = currentOriginal * (currentRate - priorRate);
      localImpact = (currentOriginal - priorOriginal) * priorRate;
      final currentDps = _totalDps(currentRows, actions);
      final priorDps = _totalDps(priorRows, actions);
      matched =
          currentDps != null &&
          priorDps != null &&
          currentDps > Decimal.zero &&
          priorDps > Decimal.zero;
      if (matched) {
        final currentShares = (currentOriginal / currentDps).toDecimal(
          scaleOnInfinitePrecision: 16,
        );
        final priorShares = (priorOriginal / priorDps).toDecimal(
          scaleOnInfinitePrecision: 16,
        );
        holdingImpact = (currentShares - priorShares) * priorDps * priorRate;
        unitImpact = currentShares * (currentDps - priorDps) * priorRate;
        localImpact = Decimal.zero;
      }
    }
    if (currentGross == priorGross &&
        holdingImpact == Decimal.zero &&
        unitImpact == Decimal.zero &&
        fxImpact == Decimal.zero &&
        localImpact == Decimal.zero) {
      continue;
    }
    result.add(
      DividendChangeAttribution(
        assetId: id,
        assetLabel:
            (currentRows.isNotEmpty ? currentRows : priorRows).last.assetLabel,
        currentGross: currentGross,
        priorGross: priorGross,
        holdingQuantityImpact: holdingImpact,
        unitDividendImpact: unitImpact,
        fxImpact: fxImpact,
        localCombinedImpact: localImpact,
        matchedUnitDividend: matched,
      ),
    );
  }
  result.sort((a, b) => b.totalChange.abs().compareTo(a.totalChange.abs()));
  return result;
}

Decimal? _totalDps(
  List<DividendCenterEvent> rows,
  Map<String, CorporateAction> actions,
) {
  var total = Decimal.zero;
  for (final row in rows) {
    final action = actions[_actionKey(row.assetId, row.event.journalEntryId)];
    final dps = switch (action) {
      CashDividendAction value => value.amountPerShare,
      DripAction value => value.amountPerShare,
      _ => null,
    };
    if (dps == null || dps <= Decimal.zero) return null;
    total += dps;
  }
  return total;
}

double _unitDividendMatchRatio(
  List<DividendCenterEvent> rows,
  Map<String, CorporateAction> actions,
) {
  final attributable = rows
      .where((row) => row.assetId != 'unattributed')
      .toList();
  if (attributable.isEmpty) return 0;
  final matches = attributable.where((row) {
    final action = actions[_actionKey(row.assetId, row.event.journalEntryId)];
    return action is CashDividendAction || action is DripAction;
  }).length;
  return matches / attributable.length;
}

DividendResilienceConfidence _confidence({
  required int observedMonths,
  required int excludedEventCount,
  required int attributedRows,
  required int totalRows,
  required double unitDividendMatchRatio,
}) {
  final attributionRatio = totalRows == 0 ? 0.0 : attributedRows / totalRows;
  final sourceTotal = totalRows + excludedEventCount;
  final includedRatio = sourceTotal == 0 ? 0.0 : totalRows / sourceTotal;
  if (observedMonths >= 24 &&
      excludedEventCount == 0 &&
      attributionRatio >= 0.9 &&
      unitDividendMatchRatio >= 0.75) {
    return DividendResilienceConfidence.high;
  }
  if (observedMonths >= 12 && attributionRatio >= 0.6 && includedRatio >= 0.8) {
    return DividendResilienceConfidence.medium;
  }
  return DividendResilienceConfidence.low;
}

List<DividendCenterEvent> _inWindow(
  List<DividendCenterEvent> rows,
  DateTime start,
  DateTime end,
) => [
  for (final row in rows)
    if (!row.event.date.toUtc().isBefore(start) &&
        row.event.date.toUtc().isBefore(end))
      row,
];

Map<String, List<DividendCenterEvent>> _groupByAsset(
  List<DividendCenterEvent> rows,
) {
  final result = <String, List<DividendCenterEvent>>{};
  for (final row in rows) {
    result.putIfAbsent(row.assetId, () => []).add(row);
  }
  return result;
}

Decimal _gross(Iterable<DividendCenterEvent> rows) =>
    rows.fold(Decimal.zero, (sum, row) => sum + row.grossInBase);

Decimal _net(Iterable<DividendCenterEvent> rows) =>
    rows.fold(Decimal.zero, (sum, row) => sum + row.netInBase);

Decimal _originalGross(Iterable<DividendCenterEvent> rows) => rows.fold(
  Decimal.zero,
  (sum, row) => sum + row.event.originalAmount + row.withholdingOriginal,
);

bool _singleCurrency(List<DividendCenterEvent> rows) {
  final currencies = <String>{};
  for (final row in rows) {
    currencies.add(row.event.currency.trim().toUpperCase());
    if (row.withholdingOriginal > Decimal.zero) {
      currencies.add(row.withholdingCurrency.trim().toUpperCase());
    }
  }
  return currencies.length <= 1;
}

String _transactionId(CorporateAction action) => switch (action) {
  CashDividendAction value => value.transactionId,
  DripAction value => value.transactionId,
  _ => action.id,
};

String _actionKey(String assetId, String transactionId) =>
    '$assetId::$transactionId';

DateTime _month(DateTime value) => DateTime.utc(value.year, value.month);

DateTime _addMonths(DateTime value, int delta) =>
    DateTime.utc(value.year, value.month + delta);

int _monthDistance(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;
