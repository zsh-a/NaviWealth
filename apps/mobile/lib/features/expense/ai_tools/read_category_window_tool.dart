/// `read_category_window` — device port (Scoped Detail).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/read_category_window.rs`; primary logic a
/// port of `scoped_detail::category_window::filter_and_sanitise`. The
/// backend scans D1 journal_entries+postings and filters on
/// `journal_entries.payload.category`; the device reads the same truth
/// from Drift via `journalEntriesWithPostingsStreamProvider` (no D1, no
/// freshness gate — §4.6.1).
///
/// **The defining device divergence (§4.6.3 — "category 即支出账户"):**
/// the typed [JournalEntry] carries *no* `payload.category` axis — on
/// device a "category" *is* an `AccountSide.expense` account (exactly
/// the model `JournalEntryRepository.watchExpenses` materialises). So
/// the required `category` input is **semantically remapped** to the
/// expense account(s) it names (by id, else case-insensitive
/// equals-or-contains on the account name) and an entry "belongs to"
/// the category iff it has a posting on one of those accounts; the
/// per-entry amount/currency is that expense leg (the device's
/// authoritative expense truth, not the backend's "sum positive
/// non-asset legs" D1 heuristic — they coincide for a normal expense
/// JE). A `device_note` always states the remap and, when the category
/// names no expense account, says so explicitly (empty ≠ "no
/// transactions" — same "surface, don't silently mislead" stance as
/// `read_account_window`). Like its siblings: HMAC dropped → real `note_excerpt` (data
/// never leaves the device); mandatory `purpose` + hard caps (≤31d,
/// ≤50) preserved for the AiTrace audit.
library;

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/domain/values/expense_category_taxonomy.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/scoped/scoped_window.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

class ReadCategoryWindowTool implements DeviceTool {
  const ReadCategoryWindowTool();

  @override
  String get name => 'read_category_window';

  // Originally ported from backend `read_category_window.rs`; updated
  // so it only references tools advertised on device.
  @override
  String get description =>
      'Scoped Detail 工具：返回某一类目在指定时间窗口内的交易明细（drill-down）。'
      '只在用户问「为什么 / 哪些」需要例证时调用 —— 默认应当先用 '
      'get_cashflow_buckets 的聚合结果回答。'
      '硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：'
      'merchant_hashed（同用户内稳定，跨用户不可逆）+ account_kind（不返名字）。'
      'purpose 必填，用于 AiTrace 审计。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['category', 'from', 'to', 'purpose'],
    'properties': {
      'category': {
        'type': 'string',
        'description': '类目（如 dining / coffee / groceries / shopping）',
      },
      'from': {'type': 'string', 'description': 'ISO 日期或时间，包含；窗口起点'},
      'to': {
        'type': 'string',
        'description': 'ISO 日期或时间，不包含；窗口终点。to - from ≤ 31 天',
      },
      'purpose': {
        'type': 'string',
        'enum': kScopedPurposes.toList(),
        'description': '调用动机；写入 AiTrace 审计',
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'default': 20},
      'merchant_substring': {
        'type': 'string',
        'description': '可选；按 note 的子串过滤（hash 后明细只能数 distinct 不能搜，所以匹配在原文上做）',
      },
    },
  };

  Map<String, Object?> _bad(String message) => <String, Object?>{
    'error': message,
    'code': 'bad_request',
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final category = input['category'] is String
        ? (input['category'] as String).trim()
        : null;
    if (category == null || category.isEmpty) {
      return _bad('category required');
    }
    final fromRaw = input['from'];
    final toRaw = input['to'];
    if (fromRaw is! String) return _bad('from required');
    if (toRaw is! String) return _bad('to required');
    final from = scopedParseIso(fromRaw);
    final to = scopedParseIso(toRaw);
    if (from == null) return _bad('from not ISO date');
    if (to == null) return _bad('to not ISO date');
    final rangeErr = validateScopedRange(from, to);
    if (rangeErr != null) return _bad(rangeErr);
    final purpose = input['purpose'];
    if (purpose is! String) return _bad('purpose required');
    if (!isScopedPurpose(purpose)) {
      return _bad("purpose '$purpose' not in DisclosurePurpose enum");
    }
    final limit = parseScopedLimit(input);
    final merchantSub = input['merchant_substring'] is String
        ? (input['merchant_substring'] as String).trim()
        : null;

    final entries = await ctx.ref.read(
      journalEntriesWithPostingsStreamProvider.future,
    );
    final accounts = await ctx.ref.read(allAccountsStreamProvider.future);

    return shape(
      entries,
      accounts: accounts,
      category: category,
      from: from,
      to: to,
      limit: limit,
      purpose: purpose,
      merchantSubstring: (merchantSub != null && merchantSub.isNotEmpty)
          ? merchantSub
          : null,
    );
  }

  /// Case-insensitive equals-or-contains on the account name, plus an
  /// exact id short-circuit. Inlined (not imported from the propose
  /// scaffolding's `nameMatches`) to keep the Scoped Detail family
  /// decoupled from the write path — same semantics, no coupling.
  static bool _matchesCategory(Account a, String needle) {
    if (a.id == needle) return true;
    final category = expenseCategoryByInput(needle);
    if (category != null) {
      final systemSuffix = ':${category.accountPath}';
      if (a.id.endsWith(systemSuffix)) return true;
    }
    final h = a.name.toLowerCase();
    final n = needle.toLowerCase();
    return h == n || h.contains(n) || n.contains(h);
  }

  /// Pure port of `category_window::filter_and_sanitise` with the
  /// §4.6.3 category→expense-account remap. One row per matched entry
  /// (has a posting on a resolved expense account, date in `[from, to)`,
  /// optional `merchant_substring` substring of the narration),
  /// newest-first, truncated to `limit`. No HMAC; real `note_excerpt`.
  static Map<String, Object?> shape(
    List<JournalEntryWithPostings> entries, {
    required List<Account> accounts,
    required String category,
    required DateTime from,
    required DateTime to,
    required int limit,
    required String purpose,
    String? merchantSubstring,
  }) {
    // §4.6.3 remap: "category" → the expense account(s) it names.
    final expenseAccounts = accounts
        .where((a) => a.category == AccountSide.expense)
        .where((a) => _matchesCategory(a, category))
        .toList();
    final expenseIds = {for (final a in expenseAccounts) a.id};
    final kindById = {for (final a in expenseAccounts) a.id: a.type.name};

    final needle = merchantSubstring?.toLowerCase();

    final hits =
        <
          ({
            String id,
            BigInt amount,
            String? currency,
            String accountKind,
            DateTime date,
            String? note,
          })
        >[];
    for (final ewp in entries) {
      final date = ewp.entry.date.toUtc();
      if (date.isBefore(from) || !date.isBefore(to)) continue;

      // The category's economic legs for this entry = postings sitting
      // on a resolved expense account (the device's authoritative
      // expense truth — cf. JournalEntryRepository.watchExpenses).
      final legs = ewp.postings
          .where((p) => expenseIds.contains(p.accountId))
          .toList();
      if (legs.isEmpty) continue;

      final note = ewp.entry.narration.isEmpty ? null : ewp.entry.narration;
      if (needle != null && !(note ?? '').toLowerCase().contains(needle)) {
        continue;
      }

      var amount = BigInt.zero;
      String? currency;
      String? accountKind;
      for (final p in legs) {
        amount += (p.units * Decimal.fromInt(100)).round().toBigInt();
        currency ??= p.unit;
        accountKind ??= kindById[p.accountId];
      }
      hits.add((
        id: ewp.entry.id,
        amount: amount,
        currency: currency,
        accountKind: accountKind ?? 'unknown',
        date: date,
        note: note,
      ));
    }
    hits.sort((a, b) => b.date.compareTo(a.date));
    final totalCount = hits.length;
    final shown = hits.take(limit).toList();

    var totalMinor = BigInt.zero;
    final currencyCounts = <String, int>{};
    final txns = <Map<String, Object?>>[];
    for (final h in shown) {
      final cur = h.currency ?? '';
      if (cur.isNotEmpty) {
        currencyCounts[cur] = (currencyCounts[cur] ?? 0) + 1;
        totalMinor += h.amount;
      }
      txns.add(<String, Object?>{
        'id': h.id,
        'occurred_at': h.date.toIso8601String(),
        'amount_minor': h.amount.toString(),
        'currency': h.currency,
        'account_kind': h.accountKind,
        // §4.6.3: device-direct → no HMAC; real excerpt instead.
        'note_excerpt': h.note == null
            ? null
            : scopedExcerpt(h.note!, kScopedNoteExcerptChars),
      });
    }

    final summary = currencyCounts.length == 1
        ? <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'total_minor': totalMinor.toString(),
            'currency': currencyCounts.keys.first,
          }
        : <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'by_currency': [
              for (final e in currencyCounts.entries)
                <String, Object?>{'currency': e.key, 'count': e.value},
            ],
          };

    return <String, Object?>{
      'summary': summary,
      'transactions': txns,
      'purpose': purpose,
      'device_note': expenseAccounts.isEmpty
          ? '端侧模式下 category 即支出账户：未找到名称/ID 匹配 '
                'category=$category 的支出账户，结果为空表示「没有这个类目账户」'
                '而非「该类目没有交易」；请确认类目名或改用 Snapshot 工具。'
          : '端侧模式下 category 即支出账户：已将 category=$category 解析为 '
                '${expenseAccounts.length} 个支出账户'
                '（${expenseAccounts.map((a) => a.name).join(' / ')}），'
                '按其 posting 过滤；merchant_hashed 已去除（端侧不出设备，'
                'note_excerpt 为真实摘要）。',
    };
  }
}
