/// §5.10.10 / S5a — dedup / reconciliation against the live ledger.
///
/// Runs against the device's Drift truth (passed in as the neutral
/// [TransactionInput] shape), **not** a cloud read model: the user often
/// records a transaction manually and then ingests the statement that
/// also contains it, and the just-recorded row hasn't projected to any
/// read model yet. Only the local source of truth can judge that — this
/// is the same reasoning as §4.2's freshness gate.
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../ai_tools/local_skills/local_skills.dart';
import '../domain/ingest_models.dart';

/// Date proximity for two rows to be considered the same event. Covers
/// manual entry date vs bank settlement/posting date drift.
const Duration kIngestDedupWindow = Duration(days: 3);

/// Minor-unit slack for a "likely" (vs exact) duplicate. Mirrors the
/// refund matcher's tolerance shape so the heuristics stay consistent.
const int kIngestDedupAmountToleranceMinor = 100;
const double kIngestDedupAmountToleranceFraction = 0.01;

class DedupResult {
  const DedupResult({required this.verdict, this.targetEntryId});

  final DedupVerdict verdict;
  final String? targetEntryId;

  static const DedupResult fresh = DedupResult(verdict: DedupVerdict.newTxn);
}

/// Optional diagnostics for proving that the index narrows the candidate set.
/// Production callers can omit this object and pay no bookkeeping cost.
final class IngestDedupMetrics {
  int candidateVisits = 0;
  int descriptorComparisons = 0;
}

/// A dedup result whose target can represent an existing row or a batch row.
final class IndexedDedupResult<T extends Object> {
  const IndexedDedupResult({required this.verdict, this.target});

  final DedupVerdict verdict;
  final T? target;
}

/// Conservative index over ledger rows.
///
/// Currency/sign, UTC day and amount only reduce the search space. The final
/// decision still uses the original time, amount and description rules, so the
/// index cannot turn a non-match into a duplicate or change target ordering.
final class IngestDedupIndex<T extends Object> {
  IngestDedupIndex({this.window = kIngestDedupWindow});

  final Duration window;
  final Map<_DedupGroupKey, SplayTreeMap<DateTime, _AmountBuckets<T>>> _groups =
      <_DedupGroupKey, SplayTreeMap<DateTime, _AmountBuckets<T>>>{};
  int _nextOrdinal = 0;

  void add(TransactionInput transaction, T target) {
    final signed = parseAmountMinor(transaction.amountMinor);
    if (signed == 0) return;
    final group = _DedupGroupKey(
      transaction.currency.toUpperCase(),
      signed.isNegative,
    );
    final days = _groups.putIfAbsent(
      group,
      () => SplayTreeMap<DateTime, _AmountBuckets<T>>(),
    );
    final amounts = days.putIfAbsent(
      _utcDay(transaction.occurredAt),
      () => SplayTreeMap<int, List<_IndexedEntry<T>>>(),
    );
    amounts
        .putIfAbsent(signed.abs(), () => <_IndexedEntry<T>>[])
        .add(
          _IndexedEntry<T>(
            ordinal: _nextOrdinal++,
            transaction: transaction,
            target: target,
          ),
        );
  }

  IndexedDedupResult<T> match(
    ParsedTransaction parsed, {
    IngestDedupMetrics? metrics,
  }) {
    final signed = parsed.amountMinor;
    final amount = signed.abs();
    if (amount == 0 || window.isNegative) {
      return IndexedDedupResult<T>(verdict: DedupVerdict.newTxn);
    }
    final days =
        _groups[_DedupGroupKey(
          parsed.currency.toUpperCase(),
          signed.isNegative,
        )];
    if (days == null || days.isEmpty) {
      return IndexedDedupResult<T>(verdict: DedupVerdict.newTxn);
    }

    late final (DateTime, DateTime) dayRange;
    try {
      dayRange = (
        _utcDay(parsed.occurredAt.subtract(window)),
        _utcDay(parsed.occurredAt.add(window)),
      );
    } on ArgumentError {
      // A public custom window can exceed DateTime's representable range.
      // Scanning the populated span is conservative and preserves the linear
      // classifier's behavior for those extreme values.
      dayRange = (days.keys.first, days.keys.last);
    }
    final (firstDay, lastDay) = dayRange;

    final exact = _earliestMatch(
      parsed: parsed,
      days: days,
      firstDay: firstDay,
      lastDay: lastDay,
      minimumAmount: amount,
      maximumAmount: amount,
      requireExactAmount: true,
      metrics: metrics,
    );
    if (exact != null) {
      return IndexedDedupResult<T>(
        verdict: DedupVerdict.duplicate,
        target: exact.target,
      );
    }

    // Deliberately wider than the final 1% rule. `_withinTolerance` uses
    // double division and can round a boundary value inward for very large
    // integers; a ~2% prefilter remains a strict conservative superset.
    final percentageSlack = _ceilDivide(amount, 50);
    final lowerSlack = math.max(
      kIngestDedupAmountToleranceMinor,
      percentageSlack,
    );
    final upperSlack = lowerSlack;
    final likely = _earliestMatch(
      parsed: parsed,
      days: days,
      firstDay: firstDay,
      lastDay: lastDay,
      minimumAmount: math.max(0, amount - lowerSlack),
      maximumAmount: amount + upperSlack,
      requireExactAmount: false,
      metrics: metrics,
    );
    if (likely != null) {
      return IndexedDedupResult<T>(
        verdict: DedupVerdict.likelyDuplicate,
        target: likely.target,
      );
    }
    return IndexedDedupResult<T>(verdict: DedupVerdict.newTxn);
  }

  _IndexedEntry<T>? _earliestMatch({
    required ParsedTransaction parsed,
    required SplayTreeMap<DateTime, _AmountBuckets<T>> days,
    required DateTime firstDay,
    required DateTime lastDay,
    required int minimumAmount,
    required int maximumAmount,
    required bool requireExactAmount,
    required IngestDedupMetrics? metrics,
  }) {
    _IndexedEntry<T>? earliest;
    DateTime? day = days.containsKey(firstDay)
        ? firstDay
        : days.firstKeyAfter(firstDay);
    while (day != null && !day.isAfter(lastDay)) {
      final amounts = days[day]!;
      int? amount = amounts.containsKey(minimumAmount)
          ? minimumAmount
          : amounts.firstKeyAfter(minimumAmount);
      while (amount != null && amount <= maximumAmount) {
        if (requireExactAmount == (amount == parsed.amountMinor.abs())) {
          for (final entry in amounts[amount]!) {
            metrics?.candidateVisits++;
            final gap = parsed.occurredAt
                .difference(entry.transaction.occurredAt)
                .abs();
            if (gap <= window &&
                (requireExactAmount ||
                    _withinTolerance(parsed.amountMinor.abs(), amount))) {
              metrics?.descriptorComparisons++;
              final description = compareTransactionDescriptions(
                parsed.description,
                entry.transaction.description,
              );
              if (description.isStrong &&
                  (earliest == null || entry.ordinal < earliest.ordinal)) {
                earliest = entry;
              }
            }
          }
        }
        amount = amounts.firstKeyAfter(amount);
      }
      day = days.firstKeyAfter(day);
    }
    return earliest;
  }
}

typedef _AmountBuckets<T extends Object> =
    SplayTreeMap<int, List<_IndexedEntry<T>>>;

final class _IndexedEntry<T extends Object> {
  const _IndexedEntry({
    required this.ordinal,
    required this.transaction,
    required this.target,
  });

  final int ordinal;
  final TransactionInput transaction;
  final T target;
}

final class _DedupGroupKey {
  const _DedupGroupKey(this.currency, this.isNegative);

  final String currency;
  final bool isNegative;

  @override
  bool operator ==(Object other) =>
      other is _DedupGroupKey &&
      other.currency == currency &&
      other.isNegative == isNegative;

  @override
  int get hashCode => Object.hash(currency, isNegative);
}

DateTime _utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

int _ceilDivide(int value, int divisor) {
  final quotient = value ~/ divisor;
  return quotient + (value % divisor == 0 ? 0 : 1);
}

/// Classify [parsed] against [existing].
///
/// A same-day amount collision is not enough. We require the same sign,
/// currency, date proximity, and a strong descriptor match.
DedupResult classifyDedup(
  ParsedTransaction parsed,
  Iterable<TransactionInput> existing, {
  Duration window = kIngestDedupWindow,
}) {
  final parsedSigned = parsed.amountMinor;
  final amount = parsedSigned.abs();
  if (amount == 0) return DedupResult.fresh;

  DedupResult? likely;
  for (final e in existing) {
    if (e.currency.toUpperCase() != parsed.currency.toUpperCase()) continue;
    final gap = parsed.occurredAt.difference(e.occurredAt).abs();
    if (gap > window) continue;

    final existingSigned = parseAmountMinor(e.amountMinor);
    if (existingSigned == 0) continue;
    if (existingSigned.isNegative != parsedSigned.isNegative) continue;
    final existingAmount = existingSigned.abs();
    final descriptorMatch = compareTransactionDescriptions(
      parsed.description,
      e.description,
    );
    if (!descriptorMatch.isStrong) continue;

    if (existingAmount == amount) {
      return DedupResult(verdict: DedupVerdict.duplicate, targetEntryId: e.id);
    }

    if (_withinTolerance(amount, existingAmount)) {
      likely ??= DedupResult(
        verdict: DedupVerdict.likelyDuplicate,
        targetEntryId: e.id,
      );
    }
  }
  return likely ?? DedupResult.fresh;
}

bool _withinTolerance(int a, int b) {
  final diff = (a - b).abs();
  if (diff <= kIngestDedupAmountToleranceMinor) return true;
  final larger = a > b ? a : b;
  if (larger == 0) return false;
  return diff / larger <= kIngestDedupAmountToleranceFraction;
}
