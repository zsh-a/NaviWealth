import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/data/domain/amortization_entry.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';

/// Roll-up stats for a single [Liability], derived from its persisted
/// amortization rows + payment history. Held as a value object so the UI can
/// render the detail screen without re-running the calculator on every
/// rebuild.
class LiabilitySummary {
  const LiabilitySummary({
    required this.liability,
    required this.totalScheduledPrincipal,
    required this.totalScheduledInterest,
    required this.principalPaid,
    required this.interestPaid,
    required this.remainingPrincipal,
    required this.paidPeriods,
    required this.totalPeriods,
  });

  final Liability liability;

  /// Sum of [AmortizationEntry.principalPayment] across the *entire*
  /// schedule — equals the original principal once rounding residuals are
  /// absorbed into the last period.
  final Decimal totalScheduledPrincipal;

  /// Sum of [AmortizationEntry.interestPayment] across the entire schedule.
  /// Combined with [totalScheduledPrincipal], gives "what the loan will
  /// cost in total."
  final Decimal totalScheduledInterest;

  /// Principal already paid (from rows where [AmortizationEntry.paidAt] is
  /// set).
  final Decimal principalPaid;

  /// Interest already paid (from rows where [AmortizationEntry.paidAt] is
  /// set).
  final Decimal interestPaid;

  /// Original principal minus principal already paid.
  final Decimal remainingPrincipal;
  final int paidPeriods;
  final int totalPeriods;

  /// Interest cost as a fraction of total cost. Useful for the "of every
  /// dollar you pay, X cents goes to interest" callout. Returns zero when
  /// total payment is zero (e.g. interest-free loan).
  Decimal get interestRatio {
    final total = totalScheduledPrincipal + totalScheduledInterest;
    if (total.sign <= 0) return Decimal.zero;
    return (totalScheduledInterest / total).toDecimal(
      scaleOnInfinitePrecision: 6,
    );
  }

  /// 0..1 progress fraction. 0 = nothing paid, 1 = fully paid off.
  double get progressFraction {
    if (totalScheduledPrincipal.sign <= 0) return 0;
    final ratio = (principalPaid / totalScheduledPrincipal)
        .toDecimal(scaleOnInfinitePrecision: 6)
        .toDouble();
    if (ratio.isNaN || ratio.isInfinite) return 0;
    return ratio.clamp(0, 1);
  }

  /// Build a [LiabilitySummary] by folding over a fully-materialized
  /// schedule. Rows with `paidAt != null` count as paid.
  factory LiabilitySummary.fromSchedule({
    required Liability liability,
    required List<AmortizationEntry> schedule,
  }) {
    var totalP = Decimal.zero;
    var totalI = Decimal.zero;
    var paidP = Decimal.zero;
    var paidI = Decimal.zero;
    var paidPeriods = 0;
    for (final row in schedule) {
      totalP += row.principalPayment;
      totalI += row.interestPayment;
      if (row.paidAt != null) {
        paidP += row.principalPayment;
        paidI += row.interestPayment;
        paidPeriods++;
      }
    }
    return LiabilitySummary(
      liability: liability,
      totalScheduledPrincipal: totalP,
      totalScheduledInterest: totalI,
      principalPaid: paidP,
      interestPaid: paidI,
      remainingPrincipal: totalP - paidP,
      paidPeriods: paidPeriods,
      totalPeriods: schedule.length,
    );
  }
}
