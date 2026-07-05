/// Shared proposal scaffolding for the FinanceOS device `propose_*` tools.
/// Cross-domain envelope helpers are re-exported from
/// `core/ai/composition/proposal_envelope.dart`; this file keeps the
/// Finance-specific reference resolution + category matching used by local
/// [ProposalEnvelope] device tools.
///
/// Reference resolution reads device **typed** [Account]/asset lists
/// instead of D1 payload rows; the match semantics (`name_matches`,
/// candidate shape `{id,name,type}`) are ported exactly.
library;

import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_taxonomy.dart';

export 'package:naviwealth/core/ai/composition/proposal_envelope.dart'
    show needsClarification, proposalBadRequest, proposalNewId, readyPlan;

/// Closed expense taxonomy exposed to the `propose_expense` tool.
final List<(String, String)> kExpenseCategories = [
  for (final category in kExpenseCategoryTaxonomy)
    (category.slug, category.labelZh),
];

/// Account types `propose_account_create` may introduce (mirrors
/// `ACCOUNT_TYPES`). Manual-valuation asset types for
/// `propose_asset_valuation` (mirrors `MANUAL_VALUATION_ASSET_TYPES`).
const List<String> kProposalAccountTypes = [
  'brokerage',
  'bank',
  'cryptoWallet',
  'realEstate',
  'vehicle',
  'liability',
  'cash',
  'other',
];

/// **Deliberately distinct** from the feature-side
/// `kManualValuationAssetTypes` (`domain/models/enums.dart`), which is a
/// stricter set excluding realEstate/vehicle. The device
/// `propose_asset_valuation` must gate exactly like the original
/// backend `MANUAL_VALUATION_ASSET_TYPES` (which *does* allow
/// realEstate / vehicle); renamed to avoid the collision and the
/// wrong-set trap.
const List<String> kProposalManualValuationTypes = [
  'cash',
  'realEstate',
  'vehicle',
  'bankDepositTerm',
  'bankDepositDemand',
  'wealthProduct',
];

/// Case-insensitive contains-or-equals — verbatim `name_matches`.
bool nameMatches(String haystack, String needle) {
  final h = haystack.toLowerCase();
  final n = needle.toLowerCase();
  return h == n || h.contains(n) || n.contains(h);
}

/// Reference resolution outcome (port of `enum Resolved`).
sealed class ResolvedRef<T> {
  const ResolvedRef();
}

class ResolvedOne<T> extends ResolvedRef<T> {
  const ResolvedOne(this.row);
  final T row;
}

class ResolvedMany<T> extends ResolvedRef<T> {
  const ResolvedMany(this.candidates);
  final List<Map<String, Object?>> candidates;
}

class ResolvedNone<T> extends ResolvedRef<T> {
  const ResolvedNone();
}

/// Port of `resolve_account` over the device typed [Account] list
/// (caller passes `accountsStreamProvider`'s value — already
/// active/non-deleted, matching the backend `deleted_at IS NULL`).
/// `byId` short-circuits; otherwise `byName` fuzzy-matches, 0/1/many →
/// None/One/Many with the verbatim `{id,name,type}` candidate shape
/// (≤8).
ResolvedRef<Account> resolveAccount(
  List<Account> accounts, {
  String? byId,
  String? byName,
}) {
  if (byId != null && byId.isNotEmpty) {
    for (final a in accounts) {
      if (a.id == byId) return ResolvedOne<Account>(a);
    }
    return const ResolvedNone();
  }
  if (byName == null || byName.isEmpty) return const ResolvedNone();
  final matches = accounts.where((a) => nameMatches(a.name, byName)).toList();
  return switch (matches.length) {
    0 => const ResolvedNone(),
    1 => ResolvedOne<Account>(matches.first),
    _ => ResolvedMany<Account>([
      for (final a in matches.take(8))
        <String, Object?>{'id': a.id, 'name': a.name, 'type': a.type.name},
    ]),
  };
}

/// Port of `resolve_liability` (same `narrow_rows` semantics as
/// `resolve_account`): `by_id` short-circuits, else `by_name`
/// fuzzy-matches. Candidate shape `{id,name,type}` (≤8), verbatim.
ResolvedRef<Liability> resolveLiability(
  List<Liability> liabilities, {
  String? byId,
  String? byName,
}) {
  if (byId != null && byId.isNotEmpty) {
    for (final l in liabilities) {
      if (l.id == byId) return ResolvedOne<Liability>(l);
    }
    return const ResolvedNone();
  }
  if (byName == null || byName.isEmpty) return const ResolvedNone();
  final matches = liabilities
      .where((l) => nameMatches(l.name, byName))
      .toList();
  return switch (matches.length) {
    0 => const ResolvedNone(),
    1 => ResolvedOne<Liability>(matches.first),
    _ => ResolvedMany<Liability>([
      for (final l in matches.take(8))
        <String, Object?>{'id': l.id, 'name': l.name, 'type': l.type.name},
    ]),
  };
}

/// Port of `resolve_asset`: `by_id` short-circuits; else
/// `by_symbol ?? by_name` fuzzy-matches symbol|name. Candidate shape
/// `{id,symbol,name,type}` (≤8), verbatim.
ResolvedRef<Asset> resolveAsset(
  List<Asset> assets, {
  String? byId,
  String? bySymbol,
  String? byName,
}) {
  if (byId != null && byId.isNotEmpty) {
    for (final a in assets) {
      if (a.id == byId) return ResolvedOne<Asset>(a);
    }
    return const ResolvedNone();
  }
  final needle = (bySymbol != null && bySymbol.isNotEmpty)
      ? bySymbol
      : (byName != null && byName.isNotEmpty ? byName : null);
  if (needle == null) return const ResolvedNone();
  final matches = assets
      .where(
        (a) =>
            nameMatches(a.symbol, needle) ||
            (a.name != null && nameMatches(a.name!, needle)),
      )
      .toList();
  return switch (matches.length) {
    0 => const ResolvedNone(),
    1 => ResolvedOne<Asset>(matches.first),
    _ => ResolvedMany<Asset>([
      for (final a in matches.take(8))
        <String, Object?>{
          'id': a.id,
          'symbol': a.symbol,
          'name': a.name,
          'type': a.type.name,
        },
    ]),
  };
}

/// Category match outcome (port of `enum CategoryMatch`).
sealed class CategoryMatch {
  const CategoryMatch();
}

class CategoryExact extends CategoryMatch {
  const CategoryExact(this.slug);
  final String slug;
}

class CategoryAmbiguous extends CategoryMatch {
  const CategoryAmbiguous(this.top3);
  final List<(String, String)> top3;
}

CategoryMatch matchExpenseCategory(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return CategoryAmbiguous(_top3Categories());

  final exact = expenseCategoryByInput(trimmed);
  if (exact != null) {
    return CategoryExact(exact.slug);
  }
  final normalized = normalizeExpenseCategoryText(trimmed);
  final substrings = kExpenseCategories
      .where(
        (e) =>
            normalizeExpenseCategoryText(e.$1).contains(normalized) ||
            normalizeExpenseCategoryText(e.$2).contains(normalized) ||
            normalized.contains(normalizeExpenseCategoryText(e.$1)),
      )
      .toList();
  if (substrings.length == 1) return CategoryExact(substrings.first.$1);
  return CategoryAmbiguous(_top3Categories());
}

/// Default clarification candidates.
List<(String, String)> _top3Categories() => [
  for (final category in fallbackExpenseCategoryCandidates())
    (category.slug, category.labelZh),
];

/// RFC3339-strict check (mirrors the file-local `parse_iso` in
/// proposals.rs — date-only `YYYY-MM-DD` is rejected, unlike the
/// scoped-detail parser). Returns true iff `s` is a valid RFC3339
/// timestamp.
bool isRfc3339(String s) {
  if (!s.contains('T')) return false;
  return DateTime.tryParse(s) != null;
}

// ── shared input plumbing (ports proposals.rs) ──────────────────────────

/// `optional_str` — non-empty string field or null.
String? proposalOptionalStr(Map<String, Object?> v, String key) {
  final x = v[key];
  return (x is String && x.isNotEmpty) ? x : null;
}

/// `require_num` — number or numeric string; null when missing/invalid.
double? proposalRequireNum(Map<String, Object?> v, String key) {
  final x = v[key];
  if (x is num) return x.toDouble();
  if (x is String) return double.tryParse(x);
  return null;
}

/// `require_str` — non-empty string field; null when missing/non-string.
String? proposalRequireStr(Map<String, Object?> v, String key) {
  final x = v[key];
  return x is String ? x : null;
}

/// Match Rust `format!("{}", f64)` for summaries: `12.0` → "12",
/// `12.5` → "12.5" (the payload keeps the raw double).
String formatProposalAmount(double a) =>
    a == a.roundToDouble() ? a.toInt().toString() : a.toString();
