/// §5.10.1 Layer 3 — duplicate-charge detector.
///
/// Surfaces pairs of outflow transactions where the same merchant
/// charged the same amount within ±2 days. The pair is suppressed if
/// either side is part of a refund match (likely a duplicate that was
/// already reversed) or part of a recognised recurring pattern (the
/// monthly rent landing on the 1st and the 3rd of overlapping months
/// is not a "duplicate charge").
///
/// Conservative by design: a false positive nags the user, a false
/// negative just means we miss one. Detection only runs against
/// outflows that share currency, a strong descriptor match, and signed
/// amount within a tiny tolerance.
library;

import 'merchant_key.dart';
import 'recurring_detector.dart' show detectRecurring;
import 'refund_matcher.dart' show matchRefunds;
import 'transaction_descriptor_match.dart';
import 'transaction_input.dart';

class DuplicateChargeMatch {
  const DuplicateChargeMatch({
    required this.firstTxnId,
    required this.secondTxnId,
    required this.amountMinor,
    required this.currency,
    required this.merchantKey,
    required this.gapDays,
  });

  /// Earlier transaction id (chronological order — `firstTxnId.occurredAt
  /// <= secondTxnId.occurredAt`).
  final String firstTxnId;

  /// Later transaction id.
  final String secondTxnId;

  /// Absolute amount in minor units. Positive.
  final int amountMinor;

  final String currency;

  /// Normalised merchant identifier the pair shares.
  final String merchantKey;

  /// Whole-day gap between the two charges (always 0–2 since the
  /// detector only emits pairs within 2 days).
  final int gapDays;
}

/// Maximum allowed gap between two charges to be considered a
/// suspected duplicate. Chosen to cover same-day duplicates, the
/// next-day re-attempt that some merchants do, and an overnight
/// settlement timezone slip — but not weekly cadence.
const Duration kDuplicateChargeMaxGap = Duration(days: 2);

/// Tolerated absolute difference between the two amounts. We lock
/// this very tight (1 cent) because by definition a "duplicate"
/// should be byte-identical; partial price changes belong to the
/// refund/anomaly paths.
const int kDuplicateChargeAmountToleranceMinor = 1;

/// Returns suspicious duplicate-charge pairs. The input list does
/// **not** need to be pre-filtered; this function internally calls
/// [matchRefunds] and [detectRecurring] to skip pairs already
/// explained by a refund or a recurring pattern.
List<DuplicateChargeMatch> detectDuplicateCharges(
  Iterable<TransactionInput> txns,
) {
  // Snapshot the input once so the matchRefunds / detectRecurring /
  // pair-scan passes all see the same set.
  final input = List<TransactionInput>.from(txns);

  final excluded = <String>{};
  for (final r in matchRefunds(input)) {
    excluded
      ..add(r.originalTxnId)
      ..add(r.refundTxnId);
  }
  for (final p in detectRecurring(input)) {
    excluded.addAll(p.occurrenceIds);
  }

  final byKey = <String, List<TransactionInput>>{};
  for (final t in input) {
    if (excluded.contains(t.id)) continue;
    final amt = parseAmountMinor(t.amountMinor);
    if (amt >= 0) continue; // only outflows
    final mk = merchantKey(t.description);
    if (mk.isEmpty) continue;
    byKey
        .putIfAbsent(
          '$mk|${t.currency.toUpperCase()}',
          () => <TransactionInput>[],
        )
        .add(t);
  }

  final out = <DuplicateChargeMatch>[];
  for (final entry in byKey.entries) {
    out.addAll(_scanGroup(entry.value));
  }
  return out;
}

Iterable<DuplicateChargeMatch> _scanGroup(List<TransactionInput> group) sync* {
  if (group.length < 2) return;
  final sorted = List<TransactionInput>.from(group)
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final consumed = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    if (consumed.contains(a.id)) continue;
    final aAmt = parseAmountMinor(a.amountMinor);
    for (var j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      if (consumed.contains(b.id)) continue;
      final gap = b.occurredAt.difference(a.occurredAt);
      if (gap > kDuplicateChargeMaxGap) break;
      if (!compareTransactionDescriptions(
        a.description,
        b.description,
      ).isStrong) {
        continue;
      }
      final bAmt = parseAmountMinor(b.amountMinor);
      if ((aAmt - bAmt).abs() > kDuplicateChargeAmountToleranceMinor) continue;
      yield DuplicateChargeMatch(
        firstTxnId: a.id,
        secondTxnId: b.id,
        amountMinor: aAmt.abs(),
        currency: a.currency,
        merchantKey: merchantKey(a.description),
        gapDays: gap.inDays,
      );
      consumed
        ..add(a.id)
        ..add(b.id);
      break;
    }
  }
}
