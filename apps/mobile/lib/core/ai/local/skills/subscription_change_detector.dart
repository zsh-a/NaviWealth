/// Rule-based subscription-price-change detector.
///
/// Builds on [detectRecurring]: for each detected recurring merchant +
/// cadence, splits its occurrences chronologically in half and compares
/// the earlier-window median against the later-window median. If the
/// absolute change exceeds [kSubscriptionChangeMinFraction] AND
/// [kSubscriptionChangeMinAbsMinor] (both must trip — guards against
/// tiny merchant-side rounding moving cheap subs), emit a
/// [SubscriptionChange].
///
/// Stateless: re-runs against the full input set on every chat turn. No
/// cross-session persistence required, no OpLog plumbing — the trade-off
/// is we can only detect changes *within the window of expenses the
/// device feeds us*. Once `recurring_patterns` is persisted via OpLog
/// (future wave) we can switch to long-history comparison.
library;

import '../../contracts/task_context.dart' show AnalyticalUpload;
import 'recurring_detector.dart';
import 'transaction_input.dart';

class SubscriptionChange {
  const SubscriptionChange({
    required this.merchantKey,
    required this.cadence,
    required this.currency,
    required this.prevMedianAmountMinor,
    required this.newMedianAmountMinor,
    required this.deltaRatio,
    required this.since,
  });

  final String merchantKey;
  final RecurringCadence cadence;
  final String currency;

  /// Earlier-window median. Signed (outflows are negative).
  final int prevMedianAmountMinor;

  /// Later-window median. Signed.
  final int newMedianAmountMinor;

  /// `(newMedian - prevMedian) / |prevMedian|`. Positive when the
  /// subscription got more expensive (more negative for outflows is
  /// "more expensive" — we normalise by absolute value).
  final double deltaRatio;

  /// Earliest occurredAt in the later window — i.e. "the change started
  /// being seen since this date".
  final DateTime since;
}

/// The canonical [SubscriptionChange] → [AnalyticalUpload] conversion
/// (§4.3.3). Single source shared by the cloud
/// `ContextPack.analytical_uploads` path and the device
/// `get_subscription_changes` tool so the device tool's
/// output is exactly what the backend `subscription_changes` read
/// model mirrors (§10).
AnalyticalUpload subscriptionChangeToUpload(SubscriptionChange c) {
  return AnalyticalUpload(
    kind: 'subscription_change',
    id: '${c.merchantKey}|${c.currency}',
    payload: <String, Object?>{
      'merchant_key': c.merchantKey,
      'cadence': c.cadence.name,
      'currency': c.currency,
      'prev_amount_minor': c.prevMedianAmountMinor.toString(),
      'new_amount_minor': c.newMedianAmountMinor.toString(),
      'delta_ratio': c.deltaRatio,
      'since': c.since.toUtc().toIso8601String(),
    },
  );
}

/// 10% minimum change to flag. Below this is normal merchant variance
/// or FX wobble.
const double kSubscriptionChangeMinFraction = 0.10;

/// Minimum absolute change in minor units (100 = $1.00). Without this a
/// $0.99 → $1.10 subscription would flag at +11% even though it's a
/// 10-cent move.
const int kSubscriptionChangeMinAbsMinor = 100;

/// Minimum occurrences in EACH half-window. We need at least 2 in each
/// to compute a meaningful median.
const int kSubscriptionChangeMinPerHalf = 2;

List<SubscriptionChange> detectSubscriptionChanges(
  Iterable<TransactionInput> txns,
) {
  final patterns = detectRecurring(txns);
  if (patterns.isEmpty) return const <SubscriptionChange>[];

  // Index txns by id for occurrence lookups; recurring_detector's
  // occurrenceIds preserves chronological order.
  final byId = <String, TransactionInput>{for (final t in txns) t.id: t};

  final out = <SubscriptionChange>[];
  for (final p in patterns) {
    final occurrences = <TransactionInput>[
      for (final id in p.occurrenceIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (occurrences.length < kSubscriptionChangeMinPerHalf * 2) continue;
    final mid = occurrences.length ~/ 2;
    final earlier = occurrences.sublist(0, mid);
    final later = occurrences.sublist(mid);
    final prev = _medianSigned(earlier);
    final next = _medianSigned(later);
    if (prev == 0) continue;
    final delta = next - prev;
    if (delta.abs() < kSubscriptionChangeMinAbsMinor) continue;
    final ratio = delta / prev.abs();
    if (ratio.abs() < kSubscriptionChangeMinFraction) continue;
    out.add(
      SubscriptionChange(
        merchantKey: p.merchantKey,
        cadence: p.cadence,
        currency: p.currency,
        prevMedianAmountMinor: prev,
        newMedianAmountMinor: next,
        deltaRatio: ratio,
        since: later.first.occurredAt,
      ),
    );
  }
  return out;
}

int _medianSigned(List<TransactionInput> txns) {
  if (txns.isEmpty) return 0;
  final amounts = <int>[for (final t in txns) parseAmountMinor(t.amountMinor)]
    ..sort();
  return amounts[amounts.length ~/ 2];
}
