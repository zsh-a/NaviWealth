/// Shared proposal scaffolding for the device `propose_*` tools
/// (§4.6 W-D4.5). Verbatim Dart port of the envelope + reference
/// resolution + category matching in `apps/backend/src/ai/proposals.rs`
/// so a device-generated plan is **byte-identical** to the cloud one —
/// the existing `ProposalEnvelope`/`proposal_applier` confirm flow
/// consumes it unchanged (§4.5; §10 drift rule: a backend proposals.rs
/// change mirrors here same PR).
///
/// Reference resolution reads device **typed** [Account]/asset lists
/// instead of D1 payload rows; the match semantics (`name_matches`,
/// candidate shape `{id,name,type}`) are ported exactly.
library;

import 'package:uuid/uuid.dart';

import '../../../../../../data/domain/account.dart';
import '../../../../../../data/domain/asset.dart';
import '../../../../../../data/domain/liability.dart';

const _kUuid = Uuid();

/// Closed expense taxonomy — verbatim from `EXPENSE_CATEGORIES`
/// (slug, 中文 label), order preserved (top-3 fallback indexes into it).
const List<(String, String)> kExpenseCategories = [
  ('food', '餐饮'),
  ('transport', '交通'),
  ('housing', '房租'),
  ('entertainment', '娱乐'),
  ('medical', '医疗'),
  ('education', '教育'),
  ('shopping', '购物'),
  ('travel', '旅行'),
  ('other', '其它'),
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
/// `kManualValuationAssetTypes` (`data/domain/enums.dart`), which is a
/// stricter set excluding realEstate/vehicle. The device
/// `propose_asset_valuation` must gate exactly like the **backend**
/// `MANUAL_VALUATION_ASSET_TYPES` (which *does* allow realEstate /
/// vehicle) so the device plan and the cloud plan are identical (§10);
/// renamed to avoid the collision and the wrong-set trap.
const List<String> kProposalManualValuationTypes = [
  'cash',
  'realEstate',
  'vehicle',
  'bankDepositTerm',
  'bankDepositDemand',
  'wealthProduct',
];

/// Pre-allocated entity id (mirrors `Uuid::new_v4()` in
/// `propose_account_create`, so follow-up proposals can reference the
/// not-yet-created account).
String proposalNewId() => _kUuid.v4();

/// Port of `proposals::ready_plan`.
Map<String, Object?> readyPlan({
  required String kind,
  required String summaryZh,
  required Map<String, Object?> payload,
  List<String> warnings = const [],
  List<String> missing = const [],
}) => <String, Object?>{
  'proposal_id': _kUuid.v4(),
  'kind': kind,
  'status': 'ready',
  'summary_zh': summaryZh,
  'payload': payload,
  'warnings': warnings,
  'missing': missing,
  'candidates': null,
  'note': '前端必须显示 summary_zh 给用户确认；只有用户明确点确认后才走 Repository。',
};

/// Port of `proposals::needs_clarification`.
Map<String, Object?> needsClarification({
  required String kind,
  required String field,
  required String reason,
  required List<Map<String, Object?>> candidates,
}) => <String, Object?>{
  'proposal_id': _kUuid.v4(),
  'kind': kind,
  'status': 'needs_clarification',
  'ambiguous_field': field,
  'reason': reason,
  'candidates': candidates,
  'note': '请向用户提一个具体问题来澄清此字段；不要替用户做选择。',
};

/// Standard BadRequest tool error (mirrors how the backend
/// `AppError::BadRequest` surfaces to the model via the dispatcher).
Map<String, Object?> proposalBadRequest(String message) => <String, Object?>{
  'error': message,
  'code': 'bad_request',
};

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

/// Verbatim port of `match_expense_category`.
CategoryMatch matchExpenseCategory(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return CategoryAmbiguous(_top3Categories());
  final lc = trimmed.toLowerCase();

  for (final (slug, label) in kExpenseCategories) {
    if (slug.toLowerCase() == lc || label == trimmed) {
      return CategoryExact(slug);
    }
  }
  final substrings = kExpenseCategories
      .where(
        (e) =>
            e.$1.toLowerCase().contains(lc) ||
            e.$2.contains(trimmed) ||
            lc.contains(e.$1.toLowerCase()),
      )
      .toList();
  if (substrings.length == 1) return CategoryExact(substrings.first.$1);
  return CategoryAmbiguous(_top3Categories());
}

/// Port of `top3_categories`: food / shopping / other (indexes 0, 6,
/// last) — always includes `other` as the escape hatch.
List<(String, String)> _top3Categories() => [
  kExpenseCategories[0],
  kExpenseCategories[6],
  kExpenseCategories.last,
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
