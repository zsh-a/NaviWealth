import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/values/money.dart';
import 'cash_flow_aggregator.dart';
import 'cash_flow_kind.dart';

const Set<CashFlowKind> kPassiveIncomeKinds = {
  CashFlowKind.dividend,
  CashFlowKind.interest,
  CashFlowKind.otherIncome,
};

const Set<CashFlowKind> kOperatingCashFlowKinds = {
  CashFlowKind.salary,
  CashFlowKind.dividend,
  CashFlowKind.interest,
  CashFlowKind.capitalGains,
  CashFlowKind.otherIncome,
  CashFlowKind.expense,
};

@immutable
class PassiveIncomeHomeMetrics {
  const PassiveIncomeHomeMetrics({
    required this.totalTtm,
    required this.previousTtm,
    required this.monthlyTotals,
  });

  final Money totalTtm;
  final Money previousTtm;
  final List<Money> monthlyTotals;

  bool get hasData =>
      totalTtm.amount != Decimal.zero || previousTtm.amount != Decimal.zero;

  double? get changeRatio {
    if (previousTtm.amount == Decimal.zero) return null;
    return ((totalTtm.amount - previousTtm.amount) / previousTtm.amount)
        .toDecimal(scaleOnInfinitePrecision: 6)
        .toDouble();
  }
}

@immutable
class MonthlyCashFlowHomeMetrics {
  const MonthlyCashFlowHomeMetrics({
    required this.monthKey,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.trailingAverageNet,
  });

  final String monthKey;
  final Money inflow;
  final Money outflow;
  final Money net;
  final Money trailingAverageNet;

  bool get hasData =>
      inflow.amount != Decimal.zero || outflow.amount != Decimal.zero;

  double get progressRatio {
    final baseline = trailingAverageNet.amount.abs();
    if (baseline == Decimal.zero) return net.amount > Decimal.zero ? 1 : 0;
    return (net.amount / baseline)
        .toDecimal(scaleOnInfinitePrecision: 6)
        .toDouble()
        .clamp(-1, 1);
  }
}

PassiveIncomeHomeMetrics passiveIncomeHomeMetrics(
  CashFlowSummary summary, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  final currentKeys = _monthKeysEndingAt(current, 12);
  final previousKeys = _monthKeysEndingAt(_addMonths(current, -12), 12);
  final monthly = [
    for (final key in currentKeys)
      Money(
        _sumBuckets(summary, key, kPassiveIncomeKinds),
        summary.baseCurrency,
      ),
  ];

  return PassiveIncomeHomeMetrics(
    totalTtm: Money(
      monthly.fold(Decimal.zero, (total, value) => total + value.amount),
      summary.baseCurrency,
    ),
    previousTtm: Money(
      previousKeys.fold(
        Decimal.zero,
        (total, key) => total + _sumBuckets(summary, key, kPassiveIncomeKinds),
      ),
      summary.baseCurrency,
    ),
    monthlyTotals: List.unmodifiable(monthly),
  );
}

MonthlyCashFlowHomeMetrics monthlyCashFlowHomeMetrics(
  CashFlowSummary summary, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  final key = _monthKey(current);
  final currentBuckets = summary.buckets.where(
    (bucket) =>
        bucket.key == key && kOperatingCashFlowKinds.contains(bucket.kind),
  );
  var inflow = Decimal.zero;
  var outflow = Decimal.zero;
  for (final bucket in currentBuckets) {
    final amount = bucket.totalInBase.amount;
    if (amount > Decimal.zero) {
      inflow += amount;
    } else if (amount < Decimal.zero) {
      outflow += amount.abs();
    }
  }
  final net = inflow - outflow;

  final trailingKeys = _monthKeysEndingAt(_addMonths(current, -1), 3);
  final trailingTotal = trailingKeys.fold(
    Decimal.zero,
    (total, monthKey) =>
        total + _sumBuckets(summary, monthKey, kOperatingCashFlowKinds),
  );
  final trailingAverage = (trailingTotal / Decimal.fromInt(trailingKeys.length))
      .toDecimal(scaleOnInfinitePrecision: 6);

  return MonthlyCashFlowHomeMetrics(
    monthKey: key,
    inflow: Money(inflow, summary.baseCurrency),
    outflow: Money(outflow, summary.baseCurrency),
    net: Money(net, summary.baseCurrency),
    trailingAverageNet: Money(trailingAverage, summary.baseCurrency),
  );
}

Decimal _sumBuckets(
  CashFlowSummary summary,
  String key,
  Set<CashFlowKind> kinds,
) {
  return summary.buckets
      .where((bucket) => bucket.key == key && kinds.contains(bucket.kind))
      .fold(Decimal.zero, (total, bucket) => total + bucket.totalInBase.amount);
}

List<String> _monthKeysEndingAt(DateTime end, int count) {
  return [
    for (var offset = count - 1; offset >= 0; offset--)
      _monthKey(_addMonths(end, -offset)),
  ];
}

DateTime _addMonths(DateTime date, int delta) {
  final monthIndex = date.year * 12 + date.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  return DateTime.utc(year, month, 1);
}

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';
