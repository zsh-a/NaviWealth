import 'package:decimal/decimal.dart';

import 'physical_asset_valuation.dart';

/// Pure depreciation maths for vehicles.
///
/// Model: a constant **annual residual rate** `r` ∈ (0, 1). After `t` years
/// the value is `purchasePrice * r^t`. Fractional years interpolate
/// linearly between the two surrounding anniversary points so the curve is
/// continuous and the displayed "current" value updates daily.
///
/// We avoid `dart:math.pow` on `Decimal`/`Rational` because they lack one
/// and we need bit-stable results across devices to keep the chart
/// consistent during sync. The integer-power loop + linear interpolation
/// is enough precision for a UI estimate (well under one cent on typical
/// vehicle values, and never fluctuates between calls).
class VehicleDepreciation {
  /// Estimate value at [asOf] given purchase params + a constant
  /// [annualResidualRate].
  ///
  /// Returns `purchasePrice` if [asOf] is on or before [purchaseDate]; never
  /// returns a negative value (clamps at zero).
  static Decimal estimate({
    required Decimal purchasePrice,
    required DateTime purchaseDate,
    required Decimal annualResidualRate,
    required DateTime asOf,
  }) {
    if (!asOf.isAfter(purchaseDate)) return purchasePrice;
    if (annualResidualRate <= Decimal.zero) return Decimal.zero;
    if (annualResidualRate >= Decimal.one) return purchasePrice;

    final daysSincePurchase = asOf.difference(purchaseDate).inDays;
    // 365.2425 ≈ Gregorian average year length, scaled by 10000 so we can
    // do all the arithmetic in integers and stay bit-stable across devices.
    const int daysPerYearTimes10000 = 3652425;
    final fullYears = (daysSincePurchase * 10000) ~/ daysPerYearTimes10000;
    final dayWithinYear =
        (daysSincePurchase * 10000) - fullYears * daysPerYearTimes10000;

    Decimal valueAtAnniversary = purchasePrice;
    for (var i = 0; i < fullYears; i++) {
      valueAtAnniversary = valueAtAnniversary * annualResidualRate;
    }
    if (dayWithinYear == 0) return valueAtAnniversary;

    final valueAtNextAnniversary = valueAtAnniversary * annualResidualRate;

    // Linear interpolation between the two anniversary points. The
    // intermediate `Decimal / Decimal` returns a `Rational`; converting back
    // with a fixed scale keeps the result bit-stable across devices.
    final delta =
        (valueAtNextAnniversary - valueAtAnniversary) *
        Decimal.fromInt(dayWithinYear);
    final fraction = delta / Decimal.fromInt(daysPerYearTimes10000);
    final result =
        valueAtAnniversary + fraction.toDecimal(scaleOnInfinitePrecision: 10);
    return result < Decimal.zero ? Decimal.zero : result;
  }

  /// Build a series of monthly projection points for a chart between
  /// [from] and [to] (inclusive of both end-points). Returns at most
  /// [maxPoints] samples — strides up if the window is large.
  static List<ValuationPoint> projectMonthly({
    required Decimal purchasePrice,
    required DateTime purchaseDate,
    required Decimal annualResidualRate,
    required DateTime from,
    required DateTime to,
    int maxPoints = 96,
  }) {
    if (!to.isAfter(from)) return const [];
    final totalMonths = ((to.year - from.year) * 12) + (to.month - from.month);
    if (totalMonths <= 0) return const [];
    final stride = (totalMonths / maxPoints).ceil().clamp(1, totalMonths);
    final out = <ValuationPoint>[];
    for (var m = 0; m <= totalMonths; m += stride) {
      final at = DateTime(from.year, from.month + m, from.day);
      final value = estimate(
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
        annualResidualRate: annualResidualRate,
        asOf: at,
      );
      out.add(
        ValuationPoint(
          asOf: at,
          value: value,
          kind: ValuationPointKind.projected,
        ),
      );
    }
    return out;
  }
}
