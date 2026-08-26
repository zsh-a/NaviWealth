import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/assets/physical/domain/vehicle_depreciation.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';

import 'dashboard_granularity.dart';
import 'dashboard_models.dart';
import 'dashboard_time_range.dart';
import 'liability_balance_source.dart';

/// Top-level entry point for running the trend build in a background isolate
/// via [Isolate.run]. All parameters are plain Dart objects — safe to send
/// across isolate boundaries. The [fxRates] list is used to reconstruct a
/// [CurrencyConverter] inside the isolate.
DashboardTrend buildDashboardTrend({
  required DashboardTimeRange range,
  required String baseCurrency,
  required List<FxRate> fxRates,
  required Iterable<ManualAssetValuation> manualAssets,
  required Iterable<DashboardPhysicalAsset> physicalAssets,
  required Iterable<Liability> liabilities,
  required Map<String, List<AmortizationEntry>> liabilitySchedules,
  List<HoldingSample> securitySamples = const [],
}) {
  final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(fxRates));
  final builder = DashboardTrendBuilder(
    converter: converter,
    baseCurrency: baseCurrency,
  );
  return builder.build(
    range: range,
    manualAssets: manualAssets,
    physicalAssets: physicalAssets,
    liabilities: liabilities,
    liabilitySchedules: liabilitySchedules,
    securitySamples: securitySamples,
  );
}

enum TrendComponentQuality { unheld, observed, estimated, missing }

enum TrendPointQuality { complete, estimated, incomplete }

/// One observation on the dashboard trend chart. Mirrors
/// [NetWorthSample] but trimmed of fields the dashboard does not need
/// (cash flow, FX residual). Keeping the type local lets us evolve the
/// shim independently of the service.
class TrendPoint {
  TrendPoint({
    required this.asOf,
    required this.assets,
    required this.liabilities,
    required this.netWorth,
    this.quality = TrendPointQuality.complete,
    this.componentQualities = const {},
  });

  final DateTime asOf;
  final Money assets;
  final Money liabilities;
  final Money netWorth;
  final TrendPointQuality quality;
  final Map<String, TrendComponentQuality> componentQualities;
}

/// Result of [DashboardTrendBuilder.build].
class DashboardTrend {
  DashboardTrend({
    required this.range,
    required this.baseCurrency,
    required this.points,
    this.currencyMismatches = const [],
  });

  final DashboardTimeRange range;
  final String baseCurrency;
  final List<TrendPoint> points;

  /// Holdings excluded from one or more sample dates because no FX rate
  /// could convert them to [baseCurrency]. Mirrors the snapshot field of
  /// the same name; the dashboard merges both lists into a single banner.
  final List<CurrencyMismatch> currencyMismatches;

  bool get isEmpty => points.isEmpty;

  /// The reliable line and period baseline. It must end at the current
  /// sample; an incomplete or estimated current value makes the suffix empty.
  List<TrendPoint> get latestCompleteSegment {
    if (points.isEmpty || points.last.quality != TrendPointQuality.complete) {
      return const [];
    }
    var start = points.length - 1;
    while (start > 0 &&
        points[start - 1].quality == TrendPointQuality.complete) {
      start -= 1;
    }
    return List<TrendPoint>.unmodifiable(points.sublist(start));
  }

  /// Latest contiguous non-incomplete segment ending in an estimate. This is
  /// rendered separately (dashed) and is never used for a period delta.
  List<TrendPoint> get latestEstimatedSegment {
    if (points.isEmpty || points.last.quality != TrendPointQuality.estimated) {
      return const [];
    }
    var start = points.length - 1;
    while (start > 0 &&
        points[start - 1].quality == TrendPointQuality.estimated) {
      start -= 1;
    }
    return List<TrendPoint>.unmodifiable(points.sublist(start));
  }

  /// Continuous chartable runs for premium multi-series rendering.
  ///
  /// Incomplete samples are dropped (never plotted as zero). Estimated and
  /// complete stay in separate segments so the chart never draws a
  /// discontinuous jump across quality boundaries. Leading "all-zero"
  /// complete samples (empty book) are also trimmed so the line starts
  /// when wealth actually appears.
  List<TrendChartSegment> get chartableSegments {
    if (points.isEmpty) return const [];
    final out = <TrendChartSegment>[];
    List<TrendPoint>? buf;
    TrendPointQuality? quality;
    for (final point in points) {
      if (point.quality == TrendPointQuality.incomplete) {
        _flushChartSegment(out, quality, buf);
        buf = null;
        quality = null;
        continue;
      }
      if (quality == null || point.quality != quality) {
        _flushChartSegment(out, quality, buf);
        buf = <TrendPoint>[point];
        quality = point.quality;
        continue;
      }
      buf!.add(point);
    }
    _flushChartSegment(out, quality, buf);
    return List.unmodifiable(out);
  }

  /// First index in [points] with non-zero net worth (or assets if NW is
  /// flat-zero but assets exist). Used by the chart to crop empty lead-in.
  int? get firstMeaningfulIndex {
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.quality == TrendPointQuality.incomplete) continue;
      if (p.netWorth.amount != Decimal.zero ||
          p.assets.amount != Decimal.zero ||
          p.liabilities.amount != Decimal.zero) {
        return i;
      }
    }
    return null;
  }

  static void _flushChartSegment(
    List<TrendChartSegment> out,
    TrendPointQuality? quality,
    List<TrendPoint>? buf,
  ) {
    if (quality == null || buf == null || buf.isEmpty) return;
    // Drop leading all-zero samples inside a complete run so pre-holding
    // days never paint a flat baseline that cliffs into first funding.
    var start = 0;
    if (quality == TrendPointQuality.complete) {
      while (start < buf.length &&
          buf[start].netWorth.amount == Decimal.zero &&
          buf[start].assets.amount == Decimal.zero &&
          buf[start].liabilities.amount == Decimal.zero) {
        start += 1;
      }
    }
    final trimmed = start == 0 ? buf : buf.sublist(start);
    // A single-sample segment cannot form a polyline; keep only runs ≥ 2.
    if (trimmed.length < 2) return;
    out.add(
      TrendChartSegment(
        quality: quality,
        points: List<TrendPoint>.unmodifiable(trimmed),
      ),
    );
  }
}

/// One continuous polyline on the wealth / net-worth trend chart.
@immutable
class TrendChartSegment {
  const TrendChartSegment({required this.quality, required this.points});

  final TrendPointQuality quality;
  final List<TrendPoint> points;

  bool get isEstimated => quality == TrendPointQuality.estimated;
  bool get isComplete => quality == TrendPointQuality.complete;
}

/// Builds the net-worth trend the dashboard renders.
///
/// Builds the net-worth trend from journal-entry postings rather than
/// replaying a full transaction stream. The trend chart needs three
/// signals:
///
///   1. asset value over time (held flat for cash / deposits / wealth
///      products until valuation history lands; physical assets replay their
///      valuation observations and vehicles may project depreciation);
///   2. outstanding liability principal over time (walked through the
///      persisted amortization schedule via [AmortizationLiabilitySource]);
///   3. the difference of the two, expressed in [baseCurrency].
///
/// The result type [DashboardTrend] is intentionally narrow: it carries
/// only the data the dashboard chart renders.
class DashboardTrendBuilder {
  DashboardTrendBuilder({
    required this.converter,
    required this.baseCurrency,
    this.onCurrencyMismatch,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Optional callback invoked when an asset / liability is silently
  /// dropped from a sample because its currency cannot be converted to
  /// [baseCurrency] for the sample date. Mirrors
  /// [DashboardAggregator.onCurrencyMismatch] so the dashboard can show a
  /// single "data incomplete" banner that covers both the snapshot and
  /// the trend chart.
  final void Function(String id, String currency)? onCurrencyMismatch;

  DashboardTrend build({
    required DashboardTimeRange range,
    required Iterable<ManualAssetValuation> manualAssets,
    required Iterable<DashboardPhysicalAsset> physicalAssets,
    required Iterable<Liability> liabilities,
    required Map<String, List<AmortizationEntry>> liabilitySchedules,
    List<HoldingSample> securitySamples = const [],
  }) {
    final manualList = manualAssets.toList(growable: false);
    final physicalList = physicalAssets.toList(growable: false);
    final liabilityList = liabilities.toList(growable: false);
    final liabSnapshots = <LiabilitySnapshot>[];
    for (final liability in liabilityList) {
      final schedule = liabilitySchedules[liability.id] ?? const [];
      liabSnapshots.add(
        LiabilitySnapshot(
          id: liability.id,
          currency: liability.currency,
          initialPrincipal: liability.principal,
          startDate: liability.startDate ?? range.from,
          schedule: [
            for (final row in schedule)
              AmortizationPoint(
                dueDate: row.dueDate,
                remainingBalance: row.remainingBalance,
              ),
          ],
        ),
      );
    }
    final liabSource = AmortizationLiabilitySource(liabSnapshots);
    final securityByDate = {
      for (final sample in securitySamples) sample.asOf.toUtc(): sample,
    };
    final sampleDates = dashboardTrendSampleDates(range);

    final points = <TrendPoint>[];
    final reported = <String>{};
    final mismatches = <CurrencyMismatch>[];
    void report(String id, String currency) {
      // Each id should only fire the callback once per build, even if every
      // sample date misses its rate — the banner doesn't get more useful
      // when a single missing pair is reported 30+ times.
      if (reported.add(id)) {
        mismatches.add(CurrencyMismatch(id: id, currency: currency));
        onCurrencyMismatch?.call(id, currency);
      }
    }

    for (final date in sampleDates) {
      final componentQualities = <String, TrendComponentQuality>{};
      for (final liability in liabilityList) {
        final startDate = liability.startDate ?? range.from;
        componentQualities['liability:${liability.id}'] =
            startDate.isAfter(date)
            ? TrendComponentQuality.unheld
            : TrendComponentQuality.observed;
      }
      final assets = _valueAssets(
        date,
        manualList,
        physicalList,
        securityByDate[date.toUtc()],
        report,
        componentQualities,
      );
      final liabilitiesValue = _valueLiabilities(
        date,
        liabSource,
        report,
        componentQualities,
      );
      final quality = _pointQuality(componentQualities.values);
      points.add(
        TrendPoint(
          asOf: date,
          assets: assets,
          liabilities: liabilitiesValue,
          netWorth: assets - liabilitiesValue,
          quality: quality,
          componentQualities: Map.unmodifiable(componentQualities),
        ),
      );
    }
    return DashboardTrend(
      range: range,
      baseCurrency: baseCurrency,
      points: points,
      currencyMismatches: List.unmodifiable(mismatches),
    );
  }

  Money _valueAssets(
    DateTime date,
    List<ManualAssetValuation> manualAssets,
    List<DashboardPhysicalAsset> physicalAssets,
    HoldingSample? securities,
    void Function(String id, String currency) report,
    Map<String, TrendComponentQuality> qualities,
  ) {
    var total = Money.zero(baseCurrency);
    for (final ma in manualAssets) {
      final key = 'manual:${ma.asset.id}';
      final activeFrom = _manualActiveFrom(ma);
      if (activeFrom == null) {
        qualities[key] = ma.asset.type == AssetType.cash
            ? TrendComponentQuality.unheld
            : TrendComponentQuality.missing;
        continue;
      }
      if (date.isBefore(activeFrom)) {
        qualities[key] = TrendComponentQuality.unheld;
        continue;
      }
      final value = ma.valueAt(date);
      if (value == null) {
        qualities[key] = TrendComponentQuality.missing;
        continue;
      }
      qualities[key] = TrendComponentQuality.observed;
      // Cash can go negative (trade overdraw); include it so the trend
      // line matches the snapshot net worth.  Other manual assets with
      // non-positive values are still excluded.
      if (value.sign <= 0 && ma.asset.type != AssetType.cash) continue;
      final amount = Money(value, ma.asset.currency);
      final converted = _addInBase(total, amount, date, ma.asset.id, report);
      if (converted == null) {
        qualities[key] = TrendComponentQuality.missing;
      } else {
        total = converted;
      }
    }
    for (final pa in physicalAssets) {
      final key = 'physical:${pa.id}';
      if (_floorToUtcDay(pa.purchaseDate).isAfter(_floorToUtcDay(date))) {
        qualities[key] = TrendComponentQuality.unheld;
        continue;
      }
      final valued = _valueOfPhysicalAt(pa, date);
      qualities[key] = valued.quality;
      final value = valued.value;
      if (value.sign <= 0) continue;
      final amount = Money(value, pa.currency);
      final converted = _addInBase(total, amount, date, pa.id, report);
      if (converted == null) {
        qualities[key] = TrendComponentQuality.missing;
      } else {
        total = converted;
      }
    }
    if (securities != null) {
      for (final snapshot in securities.snapshots.values) {
        qualities['security:${snapshot.assetId}'] =
            TrendComponentQuality.observed;
        total += Money(snapshot.marketValueInBase, baseCurrency);
      }
      for (final issue in securities.issues) {
        final key = 'security:${issue.assetId}';
        switch (issue.cause) {
          case HoldingValuationIssueCause.missingPrice:
          case HoldingValuationIssueCause.currencyMismatch:
            qualities[key] = TrendComponentQuality.estimated;
            break;
          case HoldingValuationIssueCause.missingFx:
            qualities[key] = TrendComponentQuality.missing;
            report(issue.assetId, issue.currency);
        }
      }
    }
    return total;
  }

  Money _valueLiabilities(
    DateTime date,
    LiabilityBalanceSource source,
    void Function(String id, String currency) report,
    Map<String, TrendComponentQuality> qualities,
  ) {
    var total = Money.zero(baseCurrency);
    for (final balance in source.balancesOn(date)) {
      final key = 'liability:${balance.liabilityId}';
      qualities[key] = TrendComponentQuality.observed;
      final converted = _addInBase(
        total,
        balance.outstanding,
        date,
        balance.liabilityId,
        report,
      );
      if (converted == null) {
        qualities[key] = TrendComponentQuality.missing;
      } else {
        total = converted;
      }
    }
    return total;
  }

  Money? _addInBase(
    Money acc,
    Money amount,
    DateTime on,
    String id,
    void Function(String id, String currency) report,
  ) {
    if (amount.currency == baseCurrency) return acc + amount;
    try {
      return acc + converter.convert(amount, baseCurrency, on: on);
    } on FxRateNotFoundError {
      report(id, amount.currency);
      return null;
    }
  }

  DateTime? _manualActiveFrom(ManualAssetValuation valuation) {
    final observations = valuation.observations;
    final firstObservation = observations.isEmpty
        ? null
        : observations.first.observedOn;
    final metadata = ManualAssetMetadata.decode(valuation.asset.metadataJson);
    return switch (metadata) {
      DepositMetadata(:final startDate) => startDate ?? firstObservation,
      WealthProductMetadata(:final startDate) => startDate ?? firstObservation,
      _ => firstObservation,
    };
  }

  TrendPointQuality _pointQuality(Iterable<TrendComponentQuality> qualities) {
    final list = qualities.toList(growable: false);
    // Pre-holding days (every component unheld) must not plot as a flat
    // zero line that later cliffs into real balances.
    if (list.isEmpty || list.every((q) => q == TrendComponentQuality.unheld)) {
      return TrendPointQuality.incomplete;
    }
    var estimated = false;
    for (final quality in list) {
      if (quality == TrendComponentQuality.missing) {
        return TrendPointQuality.incomplete;
      }
      if (quality == TrendComponentQuality.estimated) estimated = true;
    }
    return estimated ? TrendPointQuality.estimated : TrendPointQuality.complete;
  }

  /// Value a physical asset at a historical sample date.
  ///
  /// Manual valuations are observations, not endpoints for an invented
  /// straight line: between observations we carry forward the latest known
  /// value. Vehicles with automatic depreciation project only after the last
  /// manual observation, using that observation as the model anchor.
  _PhysicalAssetValue _valueOfPhysicalAt(
    DashboardPhysicalAsset pa,
    DateTime date,
  ) {
    final asOf = _floorToUtcDay(date);
    if (pa.valuationHistory.isEmpty) {
      return _legacyPhysicalValue(pa, asOf);
    }
    DashboardPhysicalValuation? latest;
    for (final point in [
      DashboardPhysicalValuation(
        asOf: pa.purchaseDate,
        value: pa.purchasePrice,
      ),
      ...pa.valuationHistory,
    ]) {
      final pointDay = _floorToUtcDay(point.asOf);
      final latestDay = latest == null ? null : _floorToUtcDay(latest.asOf);
      // The history is already chronologically ordered by the repository.
      // Allow the later point to win on the same day so a manual valuation
      // overrides the synthetic purchase baseline deterministically.
      if (!pointDay.isAfter(asOf) &&
          (latestDay == null || !pointDay.isBefore(latestDay))) {
        latest = point;
      }
    }

    if (latest != null) {
      final rate = pa.annualResidualRate;
      if (pa.autoDepreciation &&
          pa.type == AssetType.vehicle &&
          rate != null &&
          asOf.isAfter(_floorToUtcDay(latest.asOf))) {
        return _PhysicalAssetValue(
          value: VehicleDepreciation.estimate(
            purchasePrice: latest.value,
            purchaseDate: _floorToUtcDay(latest.asOf),
            annualResidualRate: rate,
            asOf: asOf,
          ),
          quality: TrendComponentQuality.estimated,
        );
      }
      return _PhysicalAssetValue(
        value: latest.value,
        quality: TrendComponentQuality.observed,
      );
    }

    return _PhysicalAssetValue(
      value: pa.purchasePrice,
      quality: TrendComponentQuality.observed,
    );
  }

  // Preserve compatibility for callers constructing the old compact DTO
  // without history. Production assets always carry the history above.
  _PhysicalAssetValue _legacyPhysicalValue(
    DashboardPhysicalAsset pa,
    DateTime asOf,
  ) {
    final t0 = _floorToUtcDay(pa.purchaseDate);
    final t1 = pa.lastValuationAt == null
        ? null
        : _floorToUtcDay(pa.lastValuationAt!);
    if (t1 == null ||
        !t1.isAfter(t0) ||
        pa.purchasePrice == pa.currentValuation) {
      return _PhysicalAssetValue(
        value: pa.currentValuation,
        quality: TrendComponentQuality.observed,
      );
    }
    if (!asOf.isAfter(t0)) {
      return _PhysicalAssetValue(
        value: pa.purchasePrice,
        quality: TrendComponentQuality.observed,
      );
    }
    if (!asOf.isBefore(t1)) {
      return _PhysicalAssetValue(
        value: pa.currentValuation,
        quality: TrendComponentQuality.observed,
      );
    }
    final span = t1.difference(t0).inDays;
    if (span == 0) {
      return _PhysicalAssetValue(
        value: pa.currentValuation,
        quality: TrendComponentQuality.observed,
      );
    }
    final fraction =
        (Decimal.fromInt(asOf.difference(t0).inDays) / Decimal.fromInt(span))
            .toDecimal(scaleOnInfinitePrecision: 8);
    return _PhysicalAssetValue(
      value:
          pa.purchasePrice +
          ((pa.currentValuation - pa.purchasePrice) * fraction),
      quality: TrendComponentQuality.estimated,
    );
  }
}

class _PhysicalAssetValue {
  const _PhysicalAssetValue({required this.value, required this.quality});

  final Decimal value;
  final TrendComponentQuality quality;
}

DateTime _floorToUtcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

List<DateTime> dashboardTrendSampleDates(DashboardTimeRange range) {
  switch (range.granularity) {
    case NetWorthGranularity.day:
      final days = range.spanDays;
      return [
        for (var i = 0; i <= days; i++) range.from.add(Duration(days: i)),
      ];
    case NetWorthGranularity.week:
      final dates = <DateTime>[];
      var cursor = range.from;
      while (!cursor.isAfter(range.to)) {
        dates.add(cursor);
        cursor = cursor.add(const Duration(days: 7));
      }
      if (dates.isEmpty || dates.last != range.to) dates.add(range.to);
      return dates;
    case NetWorthGranularity.month:
      final dates = <DateTime>[range.from];
      var year = range.from.year;
      var month = range.from.month;
      while (true) {
        final monthEnd = DateTime.utc(year, month + 1, 0);
        if (monthEnd.isAfter(range.to)) break;
        if (monthEnd.isAfter(range.from)) dates.add(monthEnd);
        if (month == 12) {
          year += 1;
          month = 1;
        } else {
          month += 1;
        }
      }
      if (dates.last != range.to) dates.add(range.to);
      return dates;
  }
}
