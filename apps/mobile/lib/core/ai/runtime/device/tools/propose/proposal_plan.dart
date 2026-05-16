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
const List<String> kManualValuationAssetTypes = [
  'cash',
  'realEstate',
  'vehicle',
  'bankDepositTerm',
  'bankDepositDemand',
  'wealthProduct',
];

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
