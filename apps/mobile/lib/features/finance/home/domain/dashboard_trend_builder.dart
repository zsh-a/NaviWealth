import 'package:decimal/decimal.dart';
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
}

/// Builds the net-worth trend the dashboard renders.
///
/// Builds the net-worth trend from journal-entry postings rather than
/// replaying a full transaction stream. The trend chart needs three
/// signals:
///
///   1. asset value over time (held flat for cash / deposits / wealth
///      products until valuation history lands; interpolated from
///      purchase-price → current-valuation for real estate / vehicles);
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
      if (pa.purchaseDate.isAfter(date)) {
        qualities[key] = TrendComponentQuality.unheld;
        continue;
      }
      qualities[key] = TrendComponentQuality.observed;
      final value = _valueOfPhysicalAt(pa, date);
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
    var estimated = false;
    for (final quality in qualities) {
      if (quality == TrendComponentQuality.missing) {
        return TrendPointQuality.incomplete;
      }
      if (quality == TrendComponentQuality.estimated) estimated = true;
    }
    return estimated ? TrendPointQuality.estimated : TrendPointQuality.complete;
  }

  /// Linear-interpolated value of a physical asset at [date]. Anchors are
  /// `(purchaseDate, purchasePrice)` and `(lastValuationAt, currentValuation)`.
  /// Outside both anchors we clamp to the nearest endpoint — the alternative
  /// of extrapolating produced visible artifacts on the trend chart for
  /// new purchases.
  Decimal _valueOfPhysicalAt(DashboardPhysicalAsset pa, DateTime date) {
    final t0 = pa.purchaseDate;
    final v0 = pa.purchasePrice;
    final t1 = pa.lastValuationAt;
    final v1 = pa.currentValuation;
    if (t1 == null || !t1.isAfter(t0) || v0 == v1) {
      return v1;
    }
    if (!date.isAfter(t0)) return v0;
    if (!date.isBefore(t1)) return v1;
    final span = t1.difference(t0).inDays;
    if (span == 0) return v1;
    final pos = date.difference(t0).inDays;
    final fraction = Decimal.fromInt(pos) / Decimal.fromInt(span);
    final fractionDecimal = fraction.toDecimal(scaleOnInfinitePrecision: 8);
    return v0 + ((v1 - v0) * fractionDecimal);
  }
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
