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
import 'ingest_dedup_candidate.dart';

/// Date proximity for two rows to be considered the same event. Covers
/// manual entry date vs bank settlement/posting date drift.
const Duration kIngestDedupWindow = Duration(days: 3);

/// A likely match must satisfy both the absolute and relative limits.
const int kIngestDedupAmountToleranceMinor = 100;
const int kIngestDedupAmountTolerancePercent = 1;

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
  final Map<String, _IndexedEntry<T>> _identities = {};
  int _nextOrdinal = 0;

  void add(TransactionInput transaction, T target) {
    final signed = parseAmountMinor(transaction.amountMinor);
    if (signed == 0) return;
    final group = _DedupGroupKey(
      transaction.currency.toUpperCase(),
      signed.isNegative,
      _candidateKind(transaction),
    );
    final days = _groups.putIfAbsent(
      group,
      () => SplayTreeMap<DateTime, _AmountBuckets<T>>(),
    );
    final amounts = days.putIfAbsent(
      _utcDay(transaction.occurredAt),
      () => SplayTreeMap<int, List<_IndexedEntry<T>>>(),
    );
    final entry = _IndexedEntry<T>(
      ordinal: _nextOrdinal++,
      transaction: transaction,
      target: target,
    );
    if (transaction is IngestDedupCandidate &&
        transaction.sourceIdentity != null) {
      _identities.putIfAbsent(transaction.sourceIdentity!, () => entry);
    }
    amounts.putIfAbsent(signed.abs(), () => <_IndexedEntry<T>>[]).add(entry);
  }

  IndexedDedupResult<T> match(
    ParsedTransaction parsed, {
    IngestDedupMetrics? metrics,
    String? accountId,
  }) {
    final signed = parsed.amountMinor;
    final amount = signed.abs();
    if (amount == 0 || window.isNegative) {
      return IndexedDedupResult<T>(verdict: DedupVerdict.newTxn);
    }
    final identity = parsed.sourceReference?.hasUniqueScope == true
        ? parsed.sourceReference!.identity
        : null;
    final identified = identity == null ? null : _identities[identity];
    if (identified != null) {
      return IndexedDedupResult<T>(
        verdict: DedupVerdict.duplicate,
        target: identified.target,
      );
    }
    final days =
        _groups[_DedupGroupKey(
          parsed.currency.toUpperCase(),
          signed.isNegative,
          parsed.kind,
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
      verdict: DedupVerdict.duplicate,
      metrics: metrics,
      accountId: accountId,
    );
    if (exact != null) {
      return IndexedDedupResult<T>(
        verdict: DedupVerdict.duplicate,
        target: exact.target,
      );
    }

    final likely = _earliestMatch(
      parsed: parsed,
      days: days,
      firstDay: firstDay,
      lastDay: lastDay,
      minimumAmount: math.max(0, amount - kIngestDedupAmountToleranceMinor),
      maximumAmount: amount + kIngestDedupAmountToleranceMinor,
      verdict: DedupVerdict.likelyDuplicate,
      metrics: metrics,
      accountId: accountId,
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
    required DedupVerdict verdict,
    required IngestDedupMetrics? metrics,
    required String? accountId,
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
        for (final entry in amounts[amount]!) {
          metrics?.candidateVisits++;
          final gap = parsed.occurredAt
              .difference(entry.transaction.occurredAt)
              .abs();
          if (gap <= window) {
            metrics?.descriptorComparisons++;
            final decision = _candidateVerdict(
              parsed,
              entry.transaction,
              window: window,
              accountId: accountId,
            );
            if (decision == verdict &&
                (earliest == null || entry.ordinal < earliest.ordinal)) {
              earliest = entry;
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
  const _DedupGroupKey(this.currency, this.isNegative, this.kind);

  final String currency;
  final bool isNegative;
  final IngestTransactionKind kind;

  @override
  bool operator ==(Object other) =>
      other is _DedupGroupKey &&
      other.currency == currency &&
      other.isNegative == isNegative &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(currency, isNegative, kind);
}

DateTime _utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Classify [parsed] against [existing].
///
/// A same-day amount collision is not enough. We require the same sign,
/// currency, date proximity, and a strong descriptor match.
DedupResult classifyDedup(
  ParsedTransaction parsed,
  Iterable<TransactionInput> existing, {
  Duration window = kIngestDedupWindow,
  String? accountId,
}) {
  final parsedSigned = parsed.amountMinor;
  final amount = parsedSigned.abs();
  if (amount == 0 || window.isNegative) return DedupResult.fresh;
  final entries = existing.toList(growable: false);
  final identity = parsed.sourceReference?.hasUniqueScope == true
      ? parsed.sourceReference!.identity
      : null;
  if (identity != null) {
    for (final entry in entries) {
      if (entry is IngestDedupCandidate &&
          entry.sourceIdentity == identity &&
          parseAmountMinor(entry.amountMinor) != 0) {
        return DedupResult(
          verdict: DedupVerdict.duplicate,
          targetEntryId: entry.id,
        );
      }
    }
  }

  DedupResult? likely;
  for (final e in entries) {
    final verdict = _candidateVerdict(
      parsed,
      e,
      window: window,
      accountId: accountId,
    );
    if (verdict == DedupVerdict.duplicate) {
      return DedupResult(verdict: DedupVerdict.duplicate, targetEntryId: e.id);
    }

    if (verdict == DedupVerdict.likelyDuplicate) {
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
  if (diff > kIngestDedupAmountToleranceMinor) return false;
  final larger = a > b ? a : b;
  if (larger == 0) return false;
  return BigInt.from(diff) * BigInt.from(100) <=
      BigInt.from(larger) * BigInt.from(kIngestDedupAmountTolerancePercent);
}

IngestTransactionKind _candidateKind(TransactionInput entry) =>
    entry is IngestDedupCandidate
    ? entry.kind
    : parseAmountMinor(entry.amountMinor).isNegative
    ? IngestTransactionKind.expense
    : IngestTransactionKind.income;

final _descriptorTokens = RegExp(r'[一-鿿]+|[a-z0-9]+');
String _descriptor(String value) => _descriptorTokens
    .allMatches(value.toLowerCase())
    .map((match) => match.group(0)!)
    .join();

DedupVerdict _candidateVerdict(
  ParsedTransaction parsed,
  TransactionInput entry, {
  required Duration window,
  String? accountId,
}) {
  if (window.isNegative) return DedupVerdict.newTxn;
  final evidence = entry is IngestDedupCandidate ? entry : null;
  final reference = parsed.sourceReference?.hasUniqueScope == true
      ? parsed.sourceReference
      : null;
  if (reference != null && evidence?.sourceIdentity == reference.identity) {
    return DedupVerdict.duplicate;
  }
  // Distinct provider-issued ids in the same source account are distinct events.
  if (reference != null &&
      evidence?.sourceScope == reference.scope &&
      evidence?.sourceIdentity != null) {
    return DedupVerdict.newTxn;
  }
  if (_candidateKind(entry) != parsed.kind ||
      entry.currency.toUpperCase() != parsed.currency.toUpperCase() ||
      (accountId != null &&
          entry.accountId != null &&
          accountId != entry.accountId)) {
    return DedupVerdict.newTxn;
  }
  final signed = parseAmountMinor(entry.amountMinor);
  if (signed == 0 || signed.isNegative != parsed.amountMinor.isNegative) {
    return DedupVerdict.newTxn;
  }
  final gap = parsed.occurredAt.difference(entry.occurredAt).abs();
  if (gap > window) return DedupVerdict.newTxn;
  final descriptorMatch = compareTransactionDescriptions(
    parsed.description,
    entry.description,
  );
  if (!descriptorMatch.isStrong) return DedupVerdict.newTxn;
  final left = _descriptor(parsed.description);
  final right = _descriptor(entry.description);
  final exactDescription = left == right;
  // A short merchant-only manual note can be reconciled. Shared channel or
  // category words must never equate two different products.
  if (!exactDescription &&
      left != merchantKey(entry.description) &&
      right != merchantKey(parsed.description)) {
    return DedupVerdict.newTxn;
  }
  final exactAmount = parsed.amountMinor == signed;
  if (exactAmount && exactDescription && gap == Duration.zero) {
    return DedupVerdict.duplicate;
  }
  if (gap != Duration.zero &&
      (evidence?.allowDateDrift == false ||
          (parsed.dateHasTime && evidence?.dateHasTime == true))) {
    return DedupVerdict.newTxn;
  }
  if (exactAmount ||
      (exactDescription &&
          _withinTolerance(parsed.amountMinor.abs(), signed.abs()))) {
    return DedupVerdict.likelyDuplicate;
  }
  return DedupVerdict.newTxn;
}
