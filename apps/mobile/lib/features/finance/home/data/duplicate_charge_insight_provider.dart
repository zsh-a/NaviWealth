/// §5.10.1 Layer 3 — duplicate-charge dashboard insight.
///
/// Wraps the pure [detectDuplicateCharges] skill so the dashboard can
/// surface a single summarised card when the user appears to have
/// been charged twice for the same merchant within ±2 days. Only
/// outflows are inspected and refund / recurring matches are
/// excluded — see `duplicate_charge_detector.dart` for the full rule.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/ai_tools/expense_to_transaction_input.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/duplicate_charge_detector.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';

class DuplicateChargeSummary {
  const DuplicateChargeSummary({
    required this.matches,
    required this.totalAbsAmountMinor,
    required this.currency,
  });

  final List<DuplicateChargeMatch> matches;

  /// Sum of `amountMinor` across [matches] — the worst-case overcharge
  /// if every flagged pair is a real duplicate.
  final int totalAbsAmountMinor;

  /// Reporting currency. The detector groups by currency so all
  /// matches in one summary share the same currency. `null` only
  /// when [matches] is empty.
  final String? currency;

  /// `null` when there's nothing worth surfacing.
  bool get isEmpty => matches.isEmpty;

  /// Stable hash used by the dismissed-insights store so dismissing
  /// "today's duplicate-charge cluster" doesn't permanently mute
  /// future duplicates against unrelated merchants.
  String get scopeHash {
    final sorted =
        matches
            .map((m) => '${m.merchantKey}:${m.amountMinor}:${m.gapDays}')
            .toList(growable: false)
          ..sort();
    return sorted.join(',');
  }
}

/// Returns the dashboard summary, or `null` when no suspicious pair
/// is detected. The provider is sync — the detector runs over the
/// already-loaded expense list.
final duplicateChargeInsightProvider = Provider<DuplicateChargeSummary?>((ref) {
  final expenses = ref.watch(journalExpensesStreamProvider).value;
  if (expenses == null || expenses.isEmpty) return null;
  return _summarize(expenses);
});

DuplicateChargeSummary? _summarize(Iterable<Expense> expenses) {
  final txns = expenses.map(expenseToTransactionInput).toList(growable: false);
  final matches = detectDuplicateCharges(txns);
  if (matches.isEmpty) return null;
  // Detector groups by `merchantKey|currency`, so the same currency
  // recurs across every match in a single group. We pick the first
  // currency we see and assert (asserts are dev-only) the rest agree.
  final currency = matches.first.currency;
  assert(
    matches.every((m) => m.currency == currency),
    'duplicate-charge matches should share currency within one summary; '
    'got mixed: ${matches.map((m) => m.currency).toSet()}',
  );
  final total = matches.fold<int>(0, (acc, m) => acc + m.amountMinor);
  return DuplicateChargeSummary(
    matches: matches,
    totalAbsAmountMinor: total,
    currency: currency,
  );
}
