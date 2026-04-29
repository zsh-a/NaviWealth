import 'package:decimal/decimal.dart';

import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/liability.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/services/liability_balance_source.dart';
import '../../../domain/services/net_worth_service.dart';
import '../../../domain/values/money.dart';
import '../../assets/physical/data/physical_asset.dart';
import 'dashboard_time_range.dart';

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
  });

  final DashboardTimeRange range;
  final String baseCurrency;
  final List<TrendPoint> points;

  bool get isEmpty => points.isEmpty;
}

/// Builds the net-worth trend the dashboard renders.
///
/// FIR-51's [NetWorthService] is the canonical engine for analysis / FIRE /
/// XIRR — those features need full transaction-driven replay. The dashboard
/// uses a thinner shim here because the canonical Transaction stream is
/// not yet wired through Riverpod (FIR-7 scope), and the trend chart only
/// needs three signals:
///
///   1. asset value over time (held flat for cash / deposits / wealth
///      products until valuationAdjust history lands; interpolated from
///      purchase-price → current-valuation for real estate / vehicles);
///   2. outstanding liability principal over time (walked through the
///      persisted amortization schedule via the same logic
///      [AmortizationLiabilitySource] uses inside [NetWorthService]);
///   3. the difference of the two, expressed in [baseCurrency].
///
/// When the real Transaction stream lands, callers can swap this shim for
/// a thin wrapper around `NetWorthService.timeSeries(...)` without touching
/// the chart UI — the result type [DashboardTrend] is intentionally a
/// strict subset of [NetWorthSeries].
class DashboardTrendBuilder {
  DashboardTrendBuilder({
    required this.converter,
    required this.baseCurrency,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  DashboardTrend build({
    required DashboardTimeRange range,
    required Iterable<Asset> manualAssets,
    required Iterable<PhysicalAsset> physicalAssets,
    required Iterable<Liability> liabilities,
    required Map<String, List<AmortizationEntry>> liabilitySchedules,
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
    final sampleDates = _sampleDates(range);

    final points = <TrendPoint>[];
    for (final date in sampleDates) {
      final assets = _valueAssets(date, manualList, physicalList);
      final liabilitiesValue = _valueLiabilities(date, liabSource);
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
    );
  }

  Money _valueAssets(
    DateTime date,
    List<Asset> manualAssets,
    List<PhysicalAsset> physicalAssets,
  ) {
    var total = Money.zero(baseCurrency);
    for (final asset in manualAssets) {
      final price = asset.lastPrice;
      if (price == null || price.sign <= 0) continue;
      // Until valuation history is captured, hold cash / deposit / wealth
      // products flat across the window — better than dropping them.
      final amount = Money(price, asset.currency);
      total = _addInBase(total, amount, date);
    }
    for (final pa in physicalAssets) {
      if (pa.purchaseDate.isAfter(date)) continue;
      final value = _valueOfPhysicalAt(pa, date);
      if (value.sign <= 0) continue;
      final amount = Money(value, pa.currency);
      total = _addInBase(total, amount, date);
    }
    return total;
  }

  Money _valueLiabilities(DateTime date, LiabilityBalanceSource source) {
    var total = Money.zero(baseCurrency);
    for (final balance in source.balancesOn(date)) {
      total = _addInBase(total, balance.outstanding, date);
    }
    return total;
  }

  Money _addInBase(Money acc, Money amount, DateTime on) {
    if (amount.currency == baseCurrency) return acc + amount;
    try {
      return acc + converter.convert(amount, baseCurrency, on: on);
    } on FxRateNotFoundError {
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
    final fraction = Decimal.fromInt(pos) /
        Decimal.fromInt(span);
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
