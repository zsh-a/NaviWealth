/// §5.10.10 / S5a — dedup / reconciliation against the live ledger.
///
/// Runs against the device's Drift truth (passed in as the neutral
/// [TransactionInput] shape), **not** a cloud read model: the user often
/// records a transaction manually and then ingests the statement that
/// also contains it, and the just-recorded row hasn't projected to any
/// read model yet. Only the local source of truth can judge that — this
/// is the same reasoning as §4.2's freshness gate.
library;

import '../../../core/ai/local/skills/skills.dart';
import '../domain/ingest_models.dart';

/// Date proximity for two rows to be considered the same event.
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

/// Classify [parsed] against [existing]. Conservative by design: an
/// empty merchant key never matches on the key path (avoids collapsing
/// every blank-memo cash expense into one "duplicate").
DedupResult classifyDedup(
  ParsedTransaction parsed,
  Iterable<TransactionInput> existing, {
  Duration window = kIngestDedupWindow,
}) {
  final key = merchantKey(parsed.description);
  final amount = parsed.amountMinor.abs();
  if (amount == 0) return DedupResult.fresh;

  DedupResult? likely;
  for (final e in existing) {
    if (e.currency.toUpperCase() != parsed.currency.toUpperCase()) continue;
    final gap = parsed.occurredAt.difference(e.occurredAt).abs();
    if (gap > window) continue;

    final existingAmount = parseAmountMinor(e.amountMinor).abs();
    final existingKey = merchantKey(e.description);
    final keyMatch = key.isNotEmpty && key == existingKey;
    final sameDay = _sameCalendarDay(parsed.occurredAt, e.occurredAt);

    if (existingAmount == amount && (keyMatch || sameDay)) {
      return DedupResult(verdict: DedupVerdict.duplicate, targetEntryId: e.id);
    }

    if (keyMatch && _withinTolerance(amount, existingAmount)) {
      likely ??= DedupResult(
        verdict: DedupVerdict.likelyDuplicate,
        targetEntryId: e.id,
      );
    }
  }
  return likely ?? DedupResult.fresh;
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  final ua = a.toUtc();
  final ub = b.toUtc();
  return ua.year == ub.year && ua.month == ub.month && ua.day == ub.day;
}

bool _withinTolerance(int a, int b) {
  final diff = (a - b).abs();
  if (diff <= kIngestDedupAmountToleranceMinor) return true;
  final larger = a > b ? a : b;
  if (larger == 0) return false;
  return diff / larger <= kIngestDedupAmountToleranceFraction;
}
