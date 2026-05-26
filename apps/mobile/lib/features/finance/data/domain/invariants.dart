import 'package:decimal/decimal.dart';

import 'enums.dart';
import 'journal_entry.dart';
import 'posting.dart';

/// FIR-130 — base-currency FX rate lookup interface used by the JE
/// balance check. Kept narrow on purpose: the validator wants the rate
/// at the JE date and nothing else.
///
/// Production wiring forwards through [CurrencyConverter] / `fx_rates`;
/// tests pass a deterministic `Map<String, Decimal>` adapter.
abstract class FxRateSource {
  /// Returns the multiplier converting one unit of [from] into [to] at
  /// [asOf]. Identity (`from == to`) returns 1 without consulting the
  /// underlying source.
  ///
  /// May return `null` when no rate is known. Callers treat `null` as a
  /// hard error — without an FX rate the JE cannot be folded to the
  /// base currency, so we'd rather refuse the write than silently treat
  /// the missing rate as 1.
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  });
}

/// Convenience [FxRateSource] for tests and for journal entries that
/// stay in a single currency. Trips an [ArgumentError] if asked for a
/// non-identity conversion.
class IdentityFxRateSource implements FxRateSource {
  const IdentityFxRateSource();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    if (from == to) return Decimal.one;
    throw ArgumentError(
      'IdentityFxRateSource cannot convert $from -> $to; pass a real '
      'FxRateSource for multi-currency journal entries.',
    );
  }
}

/// FIR-130 — outcome of [evaluateEntryBalance]. Carries enough detail
/// for the writer to surface a useful error to the user (or for a debug
/// build to assert / log the offending JE).
class JournalEntryBalanceReport {
  const JournalEntryBalanceReport({
    required this.totalBaseWeight,
    required this.tolerance,
    required this.problems,
  });

  /// Σ(weight) folded to the base currency. Zero (within [tolerance])
  /// means the JE is balanced. Always reported even when [problems] is
  /// non-empty so callers can show "off by 0.43 USD" hints.
  final Decimal totalBaseWeight;

  /// Tolerance the report was evaluated against — the same value passed
  /// to [evaluateEntryBalance]. Carrying it lets the caller render a
  /// "needs to be within Xe-N" message without re-deriving the value.
  final Decimal tolerance;

  /// Structured problem list. Empty when the JE is valid. Each entry
  /// names a single posting (or the JE as a whole) and the reason; the
  /// validator drains every problem rather than short-circuiting so the
  /// UI can surface the full list at once.
  final List<EntryBalanceProblem> problems;

  bool get isBalanced => problems.isEmpty && totalBaseWeight.abs() <= tolerance;
}

enum EntryBalanceProblemKind {
  /// A non-fiat unit posting carries neither a `cost` nor a `price`
  /// annotation — there's no way to compute its base-currency weight,
  /// so we refuse the entry.
  rawCommodityWithoutCostOrPrice,

  /// FX rate missing from the [FxRateSource] for the leg's currency at
  /// the JE date. Not a "this leg is wrong" problem so much as
  /// "everything that depends on this rate is unverifiable".
  missingFxRate,

  /// `JournalEntry` has zero postings. Empty entries can never be
  /// balanced and are likely a bug in the writer; reject explicitly.
  emptyEntry,

  /// Σ(weight) is non-zero outside [JournalEntryBalanceReport.tolerance].
  unbalanced,
}

class EntryBalanceProblem {
  const EntryBalanceProblem({
    required this.kind,
    required this.message,
    this.postingId,
  });

  final EntryBalanceProblemKind kind;
  final String message;
  final String? postingId;
}

/// FIR-130 — default tolerance for the JE balance check. 1e-6 absorbs
/// the rounding noise from string-stored Decimals while still catching
/// genuine off-by-one cents (which differ by 1e-2).
final Decimal kDefaultBalanceTolerance = Decimal.parse('0.000001');

/// Set of [Posting.unit] values treated as fiat for the balance rule.
/// Anything **not** in this set is a commodity / security and must
/// carry a `cost` or `price` annotation.
///
/// We keep the rule structural rather than asking the [FxRateSource] for
/// known currencies because the source might genuinely not have a
/// recent rate for an exotic pair — that should fail with
/// [EntryBalanceProblemKind.missingFxRate], not be silently downgraded
/// to "this is a commodity".
bool _looksLikeFiatCode(String unit) {
  if (unit.length < 3 || unit.length > 8) return false;
  for (final code in unit.codeUnits) {
    final upper = code >= 0x61 && code <= 0x7a ? code - 0x20 : code;
    if (upper < 0x41 || upper > 0x5a) return false;
  }
  return true;
}

/// Computes the balance status of a single [JournalEntry] given its
/// [postings]. The returned [JournalEntryBalanceReport.isBalanced] is
/// the canonical "is this writeable" answer.
///
/// Algorithm:
///   1. For each posting, compute `weight`:
///      - `cost` annotation present  → `units × cost.perUnit` (cost ccy)
///      - `price` annotation present → `units × price.perUnit` (price ccy)
///      - else (must be fiat)        → `units` (unit itself)
///   2. Fold every weight to [baseCurrency] via the [fx] source at the
///      JE date.
///   3. Σ(base-weight) must be within [tolerance].
///
/// Both `cost` and `price` may coexist on a single posting (a closing
/// trade leg carries `cost` to identify the lot and `price` to record
/// the sale price); the cost is always preferred for the balance weight
/// because that's what determines whether the books balance.
JournalEntryBalanceReport evaluateEntryBalance({
  required JournalEntry entry,
  required List<Posting> postings,
  required FxRateSource fx,
  required String baseCurrency,
  Decimal? tolerance,
}) {
  final tol = tolerance ?? kDefaultBalanceTolerance;
  final problems = <EntryBalanceProblem>[];

  // Padding rows skip the balance check by design — they exist purely
  // to reconcile against an externally-known total.
  if (entry.flag == EntryFlag.padding) {
    return JournalEntryBalanceReport(
      totalBaseWeight: Decimal.zero,
      tolerance: tol,
      problems: const [],
    );
  }

  if (postings.isEmpty) {
    return JournalEntryBalanceReport(
      totalBaseWeight: Decimal.zero,
      tolerance: tol,
      problems: const [
        EntryBalanceProblem(
          kind: EntryBalanceProblemKind.emptyEntry,
          message: 'Journal entry has no postings.',
        ),
      ],
    );
  }

  var total = Decimal.zero;
  for (final p in postings) {
    final cost = p.cost;
    final price = p.price;
    final Decimal weight;
    final String weightCcy;
    if (cost != null) {
      weight = p.units * cost.perUnit;
      weightCcy = cost.currency;
    } else if (price != null) {
      weight = p.units * price.perUnit;
      weightCcy = price.currency;
    } else if (_looksLikeFiatCode(p.unit)) {
      weight = p.units;
      weightCcy = p.unit;
    } else {
      problems.add(
        EntryBalanceProblem(
          kind: EntryBalanceProblemKind.rawCommodityWithoutCostOrPrice,
          message:
              'Posting ${p.id} carries non-fiat unit "${p.unit}" but no '
              'cost or price annotation; cannot fold to base currency.',
          postingId: p.id,
        ),
      );
      continue;
    }

    final folded = weightCcy == baseCurrency
        ? weight
        : (() {
            final r = fx.rate(
              from: weightCcy,
              to: baseCurrency,
              asOf: entry.date,
            );
            if (r == null) {
              problems.add(
                EntryBalanceProblem(
                  kind: EntryBalanceProblemKind.missingFxRate,
                  message:
                      'Missing FX rate $weightCcy → $baseCurrency on '
                      '${entry.date.toIso8601String()} for posting ${p.id}.',
                  postingId: p.id,
                ),
              );
              return null;
            }
            return weight * r;
          })();
    if (folded == null) continue;
    total += folded;
  }

  if (problems.isEmpty && total.abs() > tol) {
    problems.add(
      EntryBalanceProblem(
        kind: EntryBalanceProblemKind.unbalanced,
        message: 'Σ(weight) = $total $baseCurrency exceeds tolerance ±$tol.',
      ),
    );
  }

  return JournalEntryBalanceReport(
    totalBaseWeight: total,
    tolerance: tol,
    problems: List.unmodifiable(problems),
  );
}

/// Convenience wrapper around [evaluateEntryBalance] for callers that
/// only need the boolean answer. Use the report variant when you want
/// to surface the offending postings to the user.
bool entryIsBalanced({
  required JournalEntry entry,
  required List<Posting> postings,
  required FxRateSource fx,
  required String baseCurrency,
  Decimal? tolerance,
}) => evaluateEntryBalance(
  entry: entry,
  postings: postings,
  fx: fx,
  baseCurrency: baseCurrency,
  tolerance: tolerance,
).isBalanced;
