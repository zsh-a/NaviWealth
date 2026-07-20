import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

import 'dividend_center.dart';
import 'dividend_comparison_window.dart';

enum DividendResilienceConfidence { low, medium, high }

enum DividendChangeDriver { holdingQuantity, unitDividend, fx, localCombined }

enum DividendCadence {
  monthly,
  quarterly,
  semiAnnual,
  annual,
  irregular,
  unknown,
}

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
    required this.recordedMonthCount,
    required this.expectedPaymentCount,
    required this.missingExpectedPaymentCount,
    required this.irregularAssetCount,
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
  final int recordedMonthCount;
  final int expectedPaymentCount;
  final int missingExpectedPaymentCount;
  final int irregularAssetCount;
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
    final actionEvidence = _DividendActionEvidence(corporateActions);

    final earliest = rows.isEmpty ? null : rows.first.event.date.toUtc();
    final periodStart = earliest == null ? null : _month(earliest);
    final periodEnd = _month(nowUtc);
    final observedMonths = periodStart == null
        ? 0
        : _monthDistance(periodStart, periodEnd) + 1;
    final activeMonths = {
      for (final row in rows) _month(row.event.date.toUtc()),
    };
    final cadenceCoverage = _cadenceCoverage(rows, now: nowUtc);
    final rolling = _rolling(rows, periodStart: periodStart, now: nowUtc);
    final full = rolling.where((point) => point.hasFullWindow).toList();
    final comparison = DividendComparisonWindow.completedMonths(nowUtc);
    final latestRows = rows
        .where((row) => comparison.containsCurrent(row.event.date))
        .toList(growable: false);
    final concentration = _concentration(latestRows);
    final retention = _retention(latestRows);
    final attributions = _attribute(
      rows,
      evidence: actionEvidence,
      window: comparison,
    );
    final matchRatio = _unitDividendMatchRatio(rows, actionEvidence);
    final confidence = _confidence(
      observedMonths: observedMonths,
      excludedEventCount: excludedEventCount,
      attributedRows: rows.where((row) => row.assetId != 'unattributed').length,
      totalRows: rows.length,
      unitDividendMatchRatio: matchRatio,
      expectedPaymentCount: cadenceCoverage.expected,
      missingExpectedPaymentCount: cadenceCoverage.missing,
      irregularAssetCount: cadenceCoverage.irregularAssets,
    );

    return DividendResilienceReport(
      periodStart: periodStart,
      periodEnd: periodEnd,
      observedMonthCount: observedMonths,
      recordedMonthCount: activeMonths.length,
      expectedPaymentCount: cadenceCoverage.expected,
      missingExpectedPaymentCount: cadenceCoverage.missing,
      irregularAssetCount: cadenceCoverage.irregularAssets,
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
  required _DividendActionEvidence evidence,
  required DividendComparisonWindow window,
}) {
  final current = _groupByAsset(
    rows.where((row) => window.containsCurrent(row.event.date)).toList(),
  );
  final prior = _groupByAsset(
    rows.where((row) => window.containsPrior(row.event.date)).toList(),
  );
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
      final currentDps = _totalDps(
        currentRows,
        evidence,
        normalizedAt: window.endExclusive,
      );
      final priorDps = _totalDps(
        priorRows,
        evidence,
        normalizedAt: window.endExclusive,
      );
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
  _DividendActionEvidence evidence, {
  required DateTime normalizedAt,
}) {
  var total = Decimal.zero;
  for (final row in rows) {
    final action = evidence.uniquePayout(row.assetId, row.event.journalEntryId);
    final dps = switch (action) {
      CashDividendAction value
          when _sameCurrency(value.currency, row.event.currency) =>
        value.amountPerShare,
      DripAction value when _sameCurrency(value.currency, row.event.currency) =>
        value.amountPerShare,
      _ => null,
    };
    if (dps == null || dps <= Decimal.zero) return null;
    final quantityFactor = evidence.quantityFactor(
      row.assetId,
      after: row.event.date,
      through: normalizedAt,
    );
    if (quantityFactor == null || quantityFactor <= Decimal.zero) return null;
    total += (dps / quantityFactor).toDecimal(scaleOnInfinitePrecision: 16);
  }
  return total;
}

double _unitDividendMatchRatio(
  List<DividendCenterEvent> rows,
  _DividendActionEvidence evidence,
) {
  final attributable = rows
      .where((row) => row.assetId != 'unattributed')
      .toList();
  if (attributable.isEmpty) return 0;
  final matches = attributable.where((row) {
    final action = evidence.uniquePayout(row.assetId, row.event.journalEntryId);
    return switch (action) {
      CashDividendAction value => _sameCurrency(
        value.currency,
        row.event.currency,
      ),
      DripAction value => _sameCurrency(value.currency, row.event.currency),
      _ => false,
    };
  }).length;
  return matches / attributable.length;
}

DividendResilienceConfidence _confidence({
  required int observedMonths,
  required int excludedEventCount,
  required int attributedRows,
  required int totalRows,
  required double unitDividendMatchRatio,
  required int expectedPaymentCount,
  required int missingExpectedPaymentCount,
  required int irregularAssetCount,
}) {
  final attributionRatio = totalRows == 0 ? 0.0 : attributedRows / totalRows;
  final sourceTotal = totalRows + excludedEventCount;
  final includedRatio = sourceTotal == 0 ? 0.0 : totalRows / sourceTotal;
  final cadenceCoverage = expectedPaymentCount == 0
      ? 0.0
      : 1 - (missingExpectedPaymentCount / expectedPaymentCount);
  if (observedMonths >= 24 &&
      excludedEventCount == 0 &&
      attributionRatio >= 0.9 &&
      unitDividendMatchRatio >= 0.75 &&
      cadenceCoverage >= 0.9 &&
      irregularAssetCount == 0) {
    return DividendResilienceConfidence.high;
  }
  if (observedMonths >= 12 &&
      attributionRatio >= 0.6 &&
      includedRatio >= 0.8 &&
      (expectedPaymentCount == 0 || cadenceCoverage >= 0.6)) {
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

bool _sameCurrency(String a, String b) =>
    a.trim().toUpperCase() == b.trim().toUpperCase();

class _DividendActionEvidence {
  _DividendActionEvidence(Iterable<CorporateAction> actions) {
    for (final action in actions) {
      switch (action) {
        case CashDividendAction() || DripAction():
          _payouts
              .putIfAbsent(
                _actionKey(action.assetId, _transactionId(action)),
                () => <CorporateAction>[],
              )
              .add(action);
        case SplitAction() || StockDividendAction():
          _quantityActions
              .putIfAbsent(action.assetId, () => <CorporateAction>[])
              .add(action);
        default:
          break;
      }
    }
    for (final rows in _quantityActions.values) {
      rows.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    }
  }

  final Map<String, List<CorporateAction>> _payouts = {};
  final Map<String, List<CorporateAction>> _quantityActions = {};

  CorporateAction? uniquePayout(String assetId, String transactionId) {
    final rows = _payouts[_actionKey(assetId, transactionId)];
    return rows?.length == 1 ? rows!.single : null;
  }

  Decimal? quantityFactor(
    String assetId, {
    required DateTime after,
    required DateTime through,
  }) {
    var factor = Decimal.one;
    for (final action
        in _quantityActions[assetId] ?? const <CorporateAction>[]) {
      final date = action.effectiveDate.toUtc();
      if (!date.isAfter(after.toUtc()) || !date.isBefore(through.toUtc())) {
        continue;
      }
      final ratio = switch (action) {
        SplitAction value => value.ratio,
        StockDividendAction value => Decimal.one + value.bonusRatio,
        _ => Decimal.one,
      };
      if (ratio <= Decimal.zero) return null;
      factor *= ratio;
    }
    return factor;
  }
}

({int expected, int missing, int irregularAssets}) _cadenceCoverage(
  List<DividendCenterEvent> rows, {
  required DateTime now,
}) {
  final byAsset = _groupByAsset(rows);
  var expected = 0;
  var missing = 0;
  var irregularAssets = 0;
  final end = _month(now);
  for (final assetRows in byAsset.values) {
    final months =
        assetRows.map((row) => _month(row.event.date.toUtc())).toSet().toList()
          ..sort();
    final cadence = _inferCadence(months);
    final interval = _cadenceMonths(cadence);
    if (cadence == DividendCadence.irregular) {
      irregularAssets++;
      continue;
    }
    if (interval == null || months.isEmpty) continue;
    final tolerance = switch (cadence) {
      DividendCadence.monthly => 0,
      DividendCadence.quarterly || DividendCadence.semiAnnual => 1,
      DividendCadence.annual => 2,
      _ => 0,
    };
    for (
      var due = months.first;
      due.isBefore(end);
      due = _addMonths(due, interval)
    ) {
      expected++;
      final matched = months.any(
        (actual) => _monthDistance(due, actual).abs() <= tolerance,
      );
      if (!matched) missing++;
    }
  }
  return (
    expected: expected,
    missing: missing,
    irregularAssets: irregularAssets,
  );
}

DividendCadence _inferCadence(List<DateTime> months) {
  if (months.length < 3) return DividendCadence.unknown;
  final gaps = <int>[];
  for (var i = 1; i < months.length; i++) {
    final gap = _monthDistance(months[i - 1], months[i]);
    if (gap > 0) gaps.add(gap);
  }
  if (gaps.length < 2) return DividendCadence.unknown;
  final sorted = [...gaps]..sort();
  final median = sorted[sorted.length ~/ 2];
  final cadence = switch (median) {
    <= 2 => DividendCadence.monthly,
    <= 5 => DividendCadence.quarterly,
    <= 8 => DividendCadence.semiAnnual,
    <= 15 => DividendCadence.annual,
    _ => DividendCadence.irregular,
  };
  final interval = _cadenceMonths(cadence);
  if (interval == null) return cadence;
  final tolerance = math.max(1, (interval * 0.4).round());
  final outliers = gaps
      .where((gap) => (gap - interval).abs() > tolerance)
      .length;
  return outliers > gaps.length / 3 ? DividendCadence.irregular : cadence;
}

int? _cadenceMonths(DividendCadence cadence) => switch (cadence) {
  DividendCadence.monthly => 1,
  DividendCadence.quarterly => 3,
  DividendCadence.semiAnnual => 6,
  DividendCadence.annual => 12,
  DividendCadence.irregular || DividendCadence.unknown => null,
};

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
