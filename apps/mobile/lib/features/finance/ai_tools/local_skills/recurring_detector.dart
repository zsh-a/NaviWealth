/// Rule-based recurring-charge detector.
///
/// Looks for repeated charges from the same merchant at a regular
/// cadence (weekly / monthly). The detector is intentionally
/// conservative: a pattern needs at least three occurrences and
/// amounts within a tight tolerance before it surfaces — false
/// positives are far more annoying than false negatives in a
/// finance app.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'merchant_key.dart';
import 'transaction_input.dart';

enum RecurringCadence { weekly, monthly }

class RecurringPattern {
  const RecurringPattern({
    required this.merchantKey,
    required this.cadence,
    required this.medianAmountMinor,
    required this.currency,
    required this.occurrenceIds,
    required this.lastSeenAt,
  });

  final String merchantKey;
  final RecurringCadence cadence;

  /// Median (not mean) so a single one-off price hike doesn't drag
  /// the representative amount.
  final int medianAmountMinor;

  final String currency;

  /// `TransactionInput.id` of every occurrence that matched the
  /// pattern, in chronological order.
  final List<String> occurrenceIds;

  final DateTime lastSeenAt;
}

/// The canonical [RecurringPattern] → [AnalyticalUpload] conversion.
///
/// `AnalyticalUpload` is a historical wire name. Today the output feeds
/// device prompt context and the `get_recurring_patterns` tool from the
/// same local heuristic, so prompt preloading and tool responses cannot drift.
AnalyticalUpload recurringPatternToUpload(RecurringPattern p) {
  return AnalyticalUpload(
    kind: 'recurring_pattern',
    id: '${p.merchantKey}|${p.currency}',
    payload: <String, Object?>{
      'merchant_key': p.merchantKey,
      'cadence': p.cadence.name,
      'median_amount_minor': p.medianAmountMinor.toString(),
      'currency': p.currency,
      'occurrences': p.occurrenceIds.length,
      'last_seen_at': p.lastSeenAt.toIso8601String(),
    },
  );
}

/// Default tolerances. Exposed for tests; production callers should
/// stick to the defaults.
const int kRecurringMinOccurrences = 3;
const Duration kRecurringMonthlyMin = Duration(days: 26);
const Duration kRecurringMonthlyMax = Duration(days: 35);
const Duration kRecurringWeeklyMin = Duration(days: 6);
const Duration kRecurringWeeklyMax = Duration(days: 9);

/// Tolerated deviation between charge amounts (5%). A subscription
/// bumping from $10.99 → $12.99 (+18%) breaks the pattern; a charge
/// bouncing $10.00 → $10.50 (5%) does not.
const double kRecurringAmountToleranceFraction = 0.05;

List<RecurringPattern> detectRecurring(Iterable<TransactionInput> txns) {
  final byMerchantCurrency = <String, List<TransactionInput>>{};
  for (final t in txns) {
    final key = merchantKey(t.description);
    if (key.isEmpty) continue;
    final group = '$key|${t.currency}';
    byMerchantCurrency.putIfAbsent(group, () => <TransactionInput>[]).add(t);
  }

  final out = <RecurringPattern>[];
  for (final entry in byMerchantCurrency.entries) {
    final group = List<TransactionInput>.from(entry.value)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (group.length < kRecurringMinOccurrences) continue;
    final pattern = _detectInGroup(group);
    if (pattern != null) out.add(pattern);
  }
  return out;
}

RecurringPattern? _detectInGroup(List<TransactionInput> group) {
  // All entries already share merchant + currency; we now look for a
  // run of N+ entries with consistent gaps and amounts.
  final amounts = group.map((t) => parseAmountMinor(t.amountMinor)).toList();
  // Median amount drives the tolerance window so a one-off price hike
  // doesn't disqualify the rest.
  final sorted = List<int>.from(amounts)..sort();
  final median = sorted[sorted.length ~/ 2];
  if (median == 0) return null;
  final tolerance = (median.abs() * kRecurringAmountToleranceFraction).ceil();
  final eligible = <TransactionInput>[
    for (var i = 0; i < group.length; i++)
      if ((amounts[i] - median).abs() <= tolerance) group[i],
  ];
  if (eligible.length < kRecurringMinOccurrences) return null;

  final cadence = _classifyCadence(eligible);
  if (cadence == null) return null;
  return RecurringPattern(
    merchantKey: merchantKey(eligible.first.description),
    cadence: cadence,
    medianAmountMinor: median,
    currency: eligible.first.currency,
    occurrenceIds: <String>[for (final e in eligible) e.id],
    lastSeenAt: eligible.last.occurredAt,
  );
}

RecurringCadence? _classifyCadence(List<TransactionInput> sortedAsc) {
  // Inspect intervals between consecutive entries. A run of at least
  // (kRecurringMinOccurrences - 1) intervals all in the same band
  // counts as a pattern.
  final intervals = <Duration>[
    for (var i = 1; i < sortedAsc.length; i++)
      sortedAsc[i].occurredAt.difference(sortedAsc[i - 1].occurredAt),
  ];
  if (intervals.length < kRecurringMinOccurrences - 1) return null;
  final allMonthly = intervals.every(
    (d) => d >= kRecurringMonthlyMin && d <= kRecurringMonthlyMax,
  );
  if (allMonthly) return RecurringCadence.monthly;
  final allWeekly = intervals.every(
    (d) => d >= kRecurringWeeklyMin && d <= kRecurringWeeklyMax,
  );
  if (allWeekly) return RecurringCadence.weekly;
  return null;
}
