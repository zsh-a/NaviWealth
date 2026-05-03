import '../../../data/repositories/account_repository.dart';

/// FIR-131 wave 3f — bridge between the legacy `expense_categories`
/// taxonomy (the [ExpenseCategoryRepository] world) and the new
/// `accounts WHERE category='expense'` tree the FIR-133 seed lays
/// down.
///
/// The expense form + AI proposal applier both still pick a legacy
/// `categoryId`; on the JE write path we need to know which expense
/// account the category maps to. Until FIR-132 retires the legacy
/// category surface entirely, this static table covers every default
/// slug from `ExpenseCategoryRepository.defaultSeeds` losslessly —
/// FIR-131 wave 3g extended the FIR-133 seed so each common slug
/// has its own dedicated account.
///
/// User-created categories (anything outside the default seed
/// prefix) still fall through to `Expenses:Other`; the JE narration
/// preserves the user's text so nothing is silently lost.
class LegacyExpenseCategoryToAccount {
  const LegacyExpenseCategoryToAccount._();

  /// Mapping from a legacy category slug to the FIR-133 expense
  /// account path suffix. Covers every slug in
  /// `ExpenseCategoryRepository.defaultSeeds`; any user-created
  /// category falls through to [_fallbackPath].
  static const Map<String, String> _slugToAccountPath = <String, String>{
    'food': 'expense:food',
    'transport': 'expense:transport',
    'rent': 'expense:housing',
    'household': 'expense:household',
    'entertainment': 'expense:entertainment',
    'medical': 'expense:medical',
    'education': 'expense:education',
    'shopping': 'expense:shopping',
    'travel': 'expense:travel',
    'communication': 'expense:communication',
    'gift': 'expense:gift',
    'other': 'expense:other',
  };

  /// Used when the legacy category id isn't a default-prefixed seed
  /// (i.e. the user created their own category and we have no
  /// mapping). All FIR-131 wave 3g default seeds are now covered by
  /// [_slugToAccountPath] explicitly.
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

  /// Inverse of [resolveAccountId]: given an expense JE leg's
  /// `accountId` (e.g. `system-account:<u>:expense:food`), recover the
  /// matching legacy `expense_categories.id` so the form's existing
  /// `CategoryGridPicker` preselects the right cell when a user re-
  /// opens an existing JE-based expense for editing.
  ///
  /// Returns `null` when the account id isn't a FIR-133 system
  /// account (caller can fall back to its own default-picking logic
  /// — same as a user-created legacy category that has no FIR-133
  /// counterpart).
  static String? legacyCategoryIdFromAccountId({
    required String expenseAccountId,
    required String ownerUserId,
  }) {
    final prefix = AccountRepository.systemAccountIdForPath(
      '',
      ownerUserId: ownerUserId,
    );
    if (!expenseAccountId.startsWith(prefix)) return null;
    final path = expenseAccountId.substring(prefix.length);
    if (!path.startsWith('expense:')) return null;
    final slug = path.substring('expense:'.length);
    // Reject deeper paths like `trading:fee` — they're not in the
    // legacy default seeds, so the picker handles them with its
    // own most-used / "other" fallback.
    if (slug.contains(':')) return null;
    // We only round-trip slugs that were in the forward map. Any
    // other slug (custom-seeded by a future PR) falls back to
    // category-not-found so the form renders its default selection.
    if (!_slugToAccountPath.values.contains('expense:$slug')) {
      return null;
    }
    return 'expense-cat-default:$slug';
  }
}
