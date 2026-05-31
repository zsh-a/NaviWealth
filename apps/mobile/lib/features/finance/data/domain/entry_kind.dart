import 'enums.dart';
import 'posting.dart';

/// Derived classification of a [JournalEntry] for UI rendering
/// (icon, color, default narration).
///
/// Computed from the postings + the involved account categories;
/// **never persisted** because the rules are deterministic over the
/// posting layout. Anything that changes the rules ships with a freshly
/// computed badge on every render.
enum EntryKind {
  /// Securities trade — touches a non-fiat asset leg + at least one
  /// cash leg on an asset account. Direction (buy vs sell) is read off
  /// the cash leg sign by [EntryKindClassification.isInflow].
  trade,

  /// Cash transfer between two asset accounts. Both legs are fiat;
  /// cross-currency transfers also fall into this bucket.
  transfer,

  /// Cash arrives from an income account (Salary / Dividend / Interest /
  /// CapitalGains / Other Income).
  income,

  /// Cash flows out into one of the expense accounts.
  expense,

  /// Liability principal payment — touches a liability account and an
  /// asset account. Optional interest expense leg may be present.
  payment,

  /// Adjustment touching an equity account against an asset commodity
  /// in the same unit (typically a stock split via `Equity:Splits`).
  adjustment,

  /// Opening balance — fiat leg on an asset (or liability) account
  /// against `Equity:OpeningBalance`. Distinguished from [income] so
  /// the UI can render a different "starting balance" icon.
  opening,

  /// Catch-all for journal entries that don't fit any rule. Lands on a
  /// neutral "edit" badge and a hand-rolled narration.
  other,
}

/// Output of [classifyEntryKind] — the derived kind plus enough metadata
/// for the badge widget to choose a directional icon (buy vs sell,
/// inflow vs outflow).
class EntryKindClassification {
  const EntryKindClassification({required this.kind, this.isInflow});

  /// Discrete kind under the classification rules.
  final EntryKind kind;

  /// Net cash flow direction relative to the user's asset accounts.
  /// `true` when the JE on the whole increases asset cash holdings,
  /// `false` when it decreases them, `null` when the JE doesn't move
  /// cash either way (split / pure adjustment / unknown).
  final bool? isInflow;
}

/// Rule-based classifier for a journal entry's UI kind. The caller
/// supplies a [resolveCategory] hook so this function stays a pure
/// fold over the postings — no DB access, no Riverpod context.
///
/// The function returns [EntryKind.other] (and `isInflow == null`) when
/// the postings can't be classified — most often because [resolveCategory]
/// returned `null` for an account the writer hasn't synced yet. That
/// keeps the UI rendering a sensible badge even while the account tree
/// is still hydrating.
EntryKindClassification classifyEntryKind({
  required List<Posting> postings,
  required AccountSide? Function(String accountId) resolveCategory,
}) {
  if (postings.isEmpty) {
    return const EntryKindClassification(kind: EntryKind.other);
  }

  // Bucket categories + record per-account/unit observations.
  final categories = <AccountSide>{};
  final assetUnits = <String, Set<String>>{}; // accountId → unit set
  var hasNonFiatLeg = false;
  var hasFiatLeg = false;
  var assetCashSum = 0.0; // signed sum across asset accounts in fiat
  final assetAccountsTouched = <String>{};

  for (final p in postings) {
    final category = resolveCategory(p.accountId);
    if (category == null) {
      return const EntryKindClassification(kind: EntryKind.other);
    }
    categories.add(category);
    final isFiat = _looksLikeFiatCode(p.unit);
    if (isFiat) {
      hasFiatLeg = true;
    } else {
      hasNonFiatLeg = true;
    }
    if (category == AccountSide.asset) {
      assetAccountsTouched.add(p.accountId);
      assetUnits.putIfAbsent(p.accountId, () => <String>{}).add(p.unit);
      if (isFiat) {
        assetCashSum += p.units.toDouble();
      }
    }
  }

  // Rule 1 — liability + asset → payment.
  if (categories.contains(AccountSide.liability) &&
      categories.contains(AccountSide.asset)) {
    return EntryKindClassification(
      kind: EntryKind.payment,
      isInflow: assetCashSum > 0,
    );
  }

  // Rule 2 — equity touching → adjustment (when commodity unit) or opening.
  if (categories.contains(AccountSide.equity)) {
    if (hasNonFiatLeg) {
      return const EntryKindClassification(kind: EntryKind.adjustment);
    }
    return EntryKindClassification(
      kind: EntryKind.opening,
      isInflow: assetCashSum > 0,
    );
  }

  // Rule 3 / 4 — income / expense always pair against an asset.
  if (categories.contains(AccountSide.income)) {
    return EntryKindClassification(
      kind: EntryKind.income,
      isInflow: assetCashSum > 0,
    );
  }
  if (categories.contains(AccountSide.expense)) {
    return EntryKindClassification(
      kind: EntryKind.expense,
      isInflow: assetCashSum > 0,
    );
  }

  // Rule 5 — two distinct asset accounts, all fiat legs → transfer.
  if (categories.length == 1 &&
      categories.first == AccountSide.asset &&
      assetAccountsTouched.length >= 2 &&
      !hasNonFiatLeg) {
    return const EntryKindClassification(
      kind: EntryKind.transfer,
      // Net of two opposing legs is zero from the user's point of view.
      isInflow: null,
    );
  }

  // Rule 6 — single asset account with both fiat and non-fiat legs → trade.
  if (categories.length == 1 &&
      categories.first == AccountSide.asset &&
      assetAccountsTouched.isNotEmpty &&
      hasNonFiatLeg &&
      hasFiatLeg) {
    return EntryKindClassification(
      kind: EntryKind.trade,
      isInflow: assetCashSum > 0,
    );
  }

  return const EntryKindClassification(kind: EntryKind.other);
}

/// Mirrors `_looksLikeFiatCode` in `invariants.dart`: a unit is fiat
/// when it's an all-letter code 3..8 chars long. Anything else is a
/// commodity / asset id. Inlined here so this file stays
/// self-contained for callers that don't import the invariant
/// validator.
bool _looksLikeFiatCode(String unit) {
  if (unit.length < 3 || unit.length > 8) return false;
  for (final code in unit.codeUnits) {
    final upper = code >= 0x61 && code <= 0x7a ? code - 0x20 : code;
    if (upper < 0x41 || upper > 0x5a) return false;
  }
  return true;
}
