import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

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
  required Iterable<PhysicalAsset> physicalAssets,
  required Iterable<Liability> liabilities,
  required Map<String, List<AmortizationEntry>> liabilitySchedules,
  Iterable<({Asset asset, HoldingSnapshot snapshot})> securitiesHoldings =
      const [],
  Map<String, List<ManualAssetValuePoint>> securityPrices = const {},
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
    securitiesHoldings: securitiesHoldings,
    securityPrices: securityPrices,
  );
}

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
  });

  final DateTime asOf;
  final Money assets;
  final Money liabilities;
  final Money netWorth;
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
    required Iterable<PhysicalAsset> physicalAssets,
    required Iterable<Liability> liabilities,
    required Map<String, List<AmortizationEntry>> liabilitySchedules,
    Iterable<({Asset asset, HoldingSnapshot snapshot})> securitiesHoldings =
        const [],
    Map<String, List<ManualAssetValuePoint>> securityPrices = const {},
  }) {
    final manualList = manualAssets.toList(growable: false);
    final physicalList = physicalAssets.toList(growable: false);
    final liabSnapshots = <LiabilitySnapshot>[];
    for (final liability in liabilities) {
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
    final secList = securitiesHoldings.toList(growable: false);
    final sampleDates = _sampleDates(range);

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
      final assets = _valueAssets(
        date,
        manualList,
        physicalList,
        secList,
        securityPrices,
        report,
      );
      final liabilitiesValue = _valueLiabilities(date, liabSource, report);
      points.add(
        TrendPoint(
          asOf: date,
          assets: assets,
          liabilities: liabilitiesValue,
          netWorth: assets - liabilitiesValue,
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
    List<PhysicalAsset> physicalAssets,
    List<({Asset asset, HoldingSnapshot snapshot})> securities,
    Map<String, List<ManualAssetValuePoint>> securityPrices,
    void Function(String id, String currency) report,
  ) {
    var total = Money.zero(baseCurrency);
    for (final ma in manualAssets) {
      final value = ma.valueAt(date);
      if (value == null) continue;
      // Cash can go negative (trade overdraw); include it so the trend
      // line matches the snapshot net worth.  Other manual assets with
      // non-positive values are still excluded.
      if (value.sign <= 0 && ma.asset.type != AssetType.cash) continue;
      final amount = Money(value, ma.asset.currency);
      total = _addInBase(total, amount, date, ma.asset.id, report);
    }
    for (final pa in physicalAssets) {
      if (pa.purchaseDate.isAfter(date)) continue;
      final value = _valueOfPhysicalAt(pa, date);
      if (value.sign <= 0) continue;
      final amount = Money(value, pa.currency);
      total = _addInBase(total, amount, date, pa.id, report);
    }
    for (final sh in securities) {
      final prices = securityPrices[sh.asset.id];
      Decimal? mv;
      if (prices != null && prices.isNotEmpty) {
        // Historical prices exist — use them for accurate per-date trend.
        // If the date is before the first observation, contribute 0 rather
        // than falling back to the current snapshot value.
        final priceVal = ManualAssetValuation(
          asset: sh.asset,
          observations: prices,
        );
        final price = priceVal.valueAt(date);
        if (price != null && price.sign > 0) {
          mv = price * sh.snapshot.quantity;
        }
      } else {
        // No historical prices at all — fall back to the current snapshot
        // value so the trend isn't left with a hole.
        mv = sh.snapshot.marketValueInAssetCurrency;
      }
      if (mv == null || mv.sign <= 0) continue;
      final amount = Money(mv, sh.asset.currency);
      total = _addInBase(total, amount, date, sh.asset.id, report);
    }
    return total;
  }

  Money _valueLiabilities(
    DateTime date,
    LiabilityBalanceSource source,
    void Function(String id, String currency) report,
  ) {
    var total = Money.zero(baseCurrency);
    for (final balance in source.balancesOn(date)) {
      total = _addInBase(
        total,
        balance.outstanding,
        date,
        balance.liabilityId,
        report,
      );
    }
    return total;
  }

  Money _addInBase(
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
      return acc;
    }
  }

  /// Linear-interpolated value of a physical asset at [date]. Anchors are
  /// `(purchaseDate, purchasePrice)` and `(lastValuationAt, currentValuation)`.
  /// Outside both anchors we clamp to the nearest endpoint — the alternative
  /// of extrapolating produced visible artifacts on the trend chart for
  /// new purchases.
  Decimal _valueOfPhysicalAt(PhysicalAsset pa, DateTime date) {
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

  static List<DateTime> _sampleDates(DashboardTimeRange range) {
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
}
