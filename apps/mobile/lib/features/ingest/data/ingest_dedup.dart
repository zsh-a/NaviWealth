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
