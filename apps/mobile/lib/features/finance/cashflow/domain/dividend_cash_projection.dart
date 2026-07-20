import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

enum DividendCashCertainty { declared, inferred }

@immutable
class DividendCashProjection {
  const DividendCashProjection({
    required this.date,
    required this.netAmount,
    required this.certainty,
    required this.hasTaxEvidence,
  });

  final DateTime date;
  final Decimal netAmount;
  final DividendCashCertainty certainty;
  final bool hasTaxEvidence;
}

/// Converts the gross composite dividend forecast into explicit net-cash
/// flows. Declared actions keep their recorded withholding; inferred amounts
/// use the observed TTM retention ratio and remain labelled as estimates.
List<DividendCashProjection> buildDividendCashProjections({
  required ProjectedDividend forecast,
  required Iterable<CorporateAction> declaredActions,
  required Iterable<HoldingSnapshot> holdings,
  required DateTime from,
  required DateTime to,
  double? observedNetRetentionRatio,
}) {
  final start = _day(from);
  final end = _day(to);
  final holdingsByAsset = {
    for (final holding in holdings) holding.assetId: holding,
  };
  final declaredByDay = <DateTime, ({Decimal gross, Decimal net})>{};
  for (final action in declaredActions) {
    final date = _day(action.effectiveDate);
    if (date.isBefore(start) || date.isAfter(end)) continue;
    final holding = holdingsByAsset[action.assetId];
    if (holding == null || holding.quantity <= Decimal.zero) continue;
    final (amountPerShare, withholding) = switch (action) {
      CashDividendAction value => (value.amountPerShare, value.withholdingTax),
      DripAction value => (value.amountPerShare, value.withholdingTax),
      _ => (null, null),
    };
    if (amountPerShare == null || withholding == null) continue;
    final gross = amountPerShare * holding.quantity;
    final safeWithholding = withholding < Decimal.zero
        ? Decimal.zero
        : withholding > gross
        ? gross
        : withholding;
    final previous = declaredByDay[date];
    declaredByDay[date] = (
      gross: (previous?.gross ?? Decimal.zero) + gross,
      net: (previous?.net ?? Decimal.zero) + gross - safeWithholding,
    );
  }

  final retention = observedNetRetentionRatio == null
      ? Decimal.one
      : Decimal.parse(observedNetRetentionRatio.clamp(0.0, 1.0).toString());
  final dates =
      <DateTime>{
          ...forecast.perAsset.keys.map(_day),
          ...declaredByDay.keys,
        }.where((date) => !date.isBefore(start) && !date.isAfter(end)).toList()
        ..sort();
  final result = <DividendCashProjection>[];
  for (final date in dates) {
    final forecastGross = forecast.perAsset[date] ?? Decimal.zero;
    final declared = declaredByDay[date];
    if (declared != null && declared.net > Decimal.zero) {
      result.add(
        DividendCashProjection(
          date: date,
          netAmount: declared.net,
          certainty: DividendCashCertainty.declared,
          hasTaxEvidence: true,
        ),
      );
    }
    final inferredGross = forecastGross - (declared?.gross ?? Decimal.zero);
    if (inferredGross > Decimal.zero) {
      result.add(
        DividendCashProjection(
          date: date,
          netAmount: inferredGross * retention,
          certainty: DividendCashCertainty.inferred,
          hasTaxEvidence: observedNetRetentionRatio != null,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

DateTime _day(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
