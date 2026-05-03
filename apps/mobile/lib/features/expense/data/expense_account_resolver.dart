import '../../../data/repositories/account_repository.dart';

/// FIR-131 wave 3f — bridge between the legacy `expense_categories`
/// taxonomy (the [ExpenseCategoryRepository] world) and the new
/// `accounts WHERE category='expense'` tree the FIR-133 seed lays
/// down.
///
/// The expense form + AI proposal applier both still pick a legacy
/// `categoryId`; on the JE write path we need to know which expense
/// account the category maps to. Until FIR-132 retires the legacy
/// category surface entirely, the mapping is a small static table:
///
///   * Slugs that have a direct counterpart in the FIR-133 seed
///     (`food`, `transport`/`transit`, `rent`/`housing`) hit their
///     dedicated account.
///   * Anything else (entertainment, medical, education, shopping,
///     travel, …) falls back to `Expenses:Other` so the JE still
///     balances and lands in the journal.
///
/// The lossy fallback is **explicit** for now: a follow-up wave can
/// extend the FIR-133 seed to cover the missing 8 slugs and round-
/// trip mapping becomes lossless. Until then the user-typed
/// `JournalEntry.narration` carries the original intent so nothing is
/// silently lost.
class LegacyExpenseCategoryToAccount {
  const LegacyExpenseCategoryToAccount._();

  /// Mapping from a legacy category slug to the FIR-133 expense
  /// account path suffix. Anything not in this map hits the fallback
  /// `expense:other` slug.
  static const Map<String, String> _slugToAccountPath = <String, String>{
    'food': 'expense:food',
    'transport': 'expense:transit',
    'rent': 'expense:housing',
    'other': 'expense:other',
  };

  /// Best-effort fallback used when the slug isn't in [_slugToAccountPath]
  /// or when the legacy category id isn't a default-prefixed seed (i.e.
  /// the user created their own category and we have no mapping).
  static const String _fallbackPath = 'expense:other';

  /// Resolve a legacy `expense_categories.id` to the FIR-133 expense
  /// account id under [ownerUserId].
  ///
  /// The legacy id format is `expense-cat-default:<slug>` for seeded
  /// categories and a UUID-like string for user-created ones. The
  /// resolver:
  ///
  ///   1. Strips the default-id prefix to recover the slug.
  ///   2. Maps the slug through [_slugToAccountPath] (with [_fallbackPath]
  ///      as the catch-all).
  ///   3. Builds the account id via [AccountRepository.systemAccountIdForPath].
  ///
  /// User-created categories that don't carry the default-id prefix
  /// short-circuit straight to the fallback account — there's no
  /// information available to do better, and the JE narration still
  /// preserves the user's text.
  static String resolveAccountId({
    required String categoryId,
    required String ownerUserId,
  }) {
    // Mirrors `ExpenseCategoryRepository._defaultIdPrefix`. Inlined
    // here so the resolver doesn't reach into the legacy repo for a
    // private helper; the constant changes mean a sync-protocol
    // change anyway, which would surface in code review either way.
    const prefix = 'expense-cat-default:';
    var path = _fallbackPath;
    if (categoryId.startsWith(prefix)) {
      final slug = categoryId.substring(prefix.length);
      path = _slugToAccountPath[slug] ?? _fallbackPath;
    }
    return AccountRepository.systemAccountIdForPath(
      path,
      ownerUserId: ownerUserId,
    );
  }
}
