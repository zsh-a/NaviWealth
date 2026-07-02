import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';

import 'cash_flow_event.dart';
import 'cash_flow_kind.dart';

enum CashFlowPeriod { month, quarter, year }

@immutable
class CashFlowSummaryRequest {
  const CashFlowSummaryRequest({required this.period});

  final CashFlowPeriod period;

  @override
  bool operator ==(Object other) =>
      other is CashFlowSummaryRequest && other.period == period;

  @override
  int get hashCode => period.hashCode;
}

@immutable
class CashFlowBucket {
  const CashFlowBucket({
    required this.key,
    required this.kind,
    required this.currency,
    required this.totalInBase,
    required this.originalTotal,
    required this.count,
  });

  final String key;
  final CashFlowKind kind;
  final String currency;
  final Money totalInBase;
  final Money originalTotal;
  final int count;
}

@immutable
class CashFlowSummary {
  const CashFlowSummary({
    required this.period,
    required this.baseCurrency,
    required this.buckets,
    required this.totalInBase,
  });

  final CashFlowPeriod period;
  final String baseCurrency;
  final List<CashFlowBucket> buckets;
  final Money totalInBase;
}

CashFlowSummary aggregateCashFlow(
  Iterable<CashFlowEvent> events, {
  required CashFlowPeriod period,
  required String baseCurrency,
}) {
  final acc = <String, _BucketAcc>{};
  var total = Decimal.zero;
  for (final event in events) {
    final key = _periodKey(event.date.toUtc(), period);
    final currency = event.currency.trim().toUpperCase();
    final accKey = '$key|${event.kind.name}|$currency';
    final bucket = acc.putIfAbsent(
      accKey,
      () => _BucketAcc(key: key, kind: event.kind, currency: currency),
    );
    bucket.base += event.signedAmount;
    bucket.original += event.originalAmount;
    bucket.count++;
    total += event.signedAmount;
  }

  final buckets =
      acc.values.map((bucket) {
        return CashFlowBucket(
          key: bucket.key,
          kind: bucket.kind,
          currency: bucket.currency,
          totalInBase: Money(bucket.base, baseCurrency),
          originalTotal: Money(bucket.original, bucket.currency),
          count: bucket.count,
        );
      }).toList()..sort((a, b) {
        final c = a.key.compareTo(b.key);
        if (c != 0) return c;
        final k = a.kind.index.compareTo(b.kind.index);
        if (k != 0) return k;
        return a.currency.compareTo(b.currency);
      });

  return CashFlowSummary(
    period: period,
    baseCurrency: baseCurrency,
    buckets: List.unmodifiable(buckets),
    totalInBase: Money(total, baseCurrency),
  );
}

Map<String, Object?> aggregateLegacyCashflowBuckets({
  required List<JournalEntryWithPostings> entries,
  required List<Asset> assets,
  required int monthsBack,
  String? currency,
  DateTime? now,
}) {
  final assetIds = {for (final a in assets) a.id};
  final acc = <String, Map<String, List<BigInt>>>{};
  for (final ewp in entries) {
    final ym = _periodKey(ewp.entry.date.toUtc(), CashFlowPeriod.month);
    for (final p in ewp.postings) {
      if (assetIds.contains(p.unit)) continue;
      if (p.units == Decimal.zero) continue;
      final minor = (p.units * Decimal.fromInt(100)).round().toBigInt();
      final byCur = acc.putIfAbsent(ym, () => <String, List<BigInt>>{});
      final b = byCur.putIfAbsent(
        p.unit,
        () => [BigInt.zero, BigInt.zero, BigInt.zero, BigInt.zero],
      );
      if (minor > BigInt.zero) {
        b[0] += minor;
        b[2] += BigInt.one;
      } else {
        b[1] += -minor;
        b[3] += BigInt.one;
      }
    }
  }

  final rows =
      <
        ({
          String ym,
          String currency,
          BigInt inflow,
          BigInt outflow,
          BigInt inCount,
          BigInt outCount,
        })
      >[];
  for (final ymEntry in acc.entries) {
    for (final curEntry in ymEntry.value.entries) {
      final b = curEntry.value;
      rows.add((
        ym: ymEntry.key,
        currency: curEntry.key,
        inflow: b[0],
        outflow: b[1],
        inCount: b[2],
        outCount: b[3],
      ));
    }
  }
  rows.sort((a, b) {
    final c = a.ym.compareTo(b.ym);
    return c != 0 ? c : a.currency.compareTo(b.currency);
  });

  final nowUtc = (now ?? DateTime.now()).toUtc();
  final toYm = _periodKey(nowUtc, CashFlowPeriod.month);
  var fromY = nowUtc.year;
  var fromM = nowUtc.month - (monthsBack - 1);
  while (fromM < 1) {
    fromM += 12;
    fromY -= 1;
  }
  final fromYm =
      '${fromY.toString().padLeft(4, '0')}-'
      '${fromM.toString().padLeft(2, '0')}';

  final series = <Map<String, Object?>>[];
  for (final r in rows) {
    if (r.ym.compareTo(fromYm) < 0 || r.ym.compareTo(toYm) > 0) continue;
    if (currency != null && r.currency != currency) continue;
    final net = r.inflow - r.outflow;
    series.add(<String, Object?>{
      'year_month': r.ym,
      'currency': r.currency,
      'inflow_minor': r.inflow.toString(),
      'outflow_minor': r.outflow.toString(),
      'net_minor': net.toString(),
      'inflow_count': r.inCount.toInt(),
      'outflow_count': r.outCount.toInt(),
    });
  }

  return <String, Object?>{
    'from': fromYm,
    'to': toYm,
    'currency': currency,
    'series': series,
    'source': 'device_ledger',
    'note':
        'Monthly inflow / outflow buckets; net_minor = inflow - outflow. '
        'Same source as net_worth_snapshot.net_flow, but split by bucket '
        'instead of accumulated.',
  };
}

String _periodKey(DateTime date, CashFlowPeriod period) {
  switch (period) {
    case CashFlowPeriod.month:
      return '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}';
    case CashFlowPeriod.quarter:
      final quarter = ((date.month - 1) ~/ 3) + 1;
      return '${date.year.toString().padLeft(4, '0')}-Q$quarter';
    case CashFlowPeriod.year:
      return date.year.toString().padLeft(4, '0');
  }
}

class _BucketAcc {
  _BucketAcc({required this.key, required this.kind, required this.currency});

  final String key;
  final CashFlowKind kind;
  final String currency;
  Decimal base = Decimal.zero;
  Decimal original = Decimal.zero;
  int count = 0;
}
