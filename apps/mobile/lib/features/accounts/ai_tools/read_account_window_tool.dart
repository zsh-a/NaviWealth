/// `read_account_window` — device port (§4.6 W-D4.4, Scoped Detail).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/read_account_window.rs`; primary logic a
/// port of `scoped_detail::account_window::filter_and_sanitise`. The
/// backend scans D1 journal_entries+postings; the device reads the
/// same truth from Drift via `journalEntriesWithPostingsStreamProvider`
/// (no D1, no freshness gate — §4.6.1).
///
/// **Device divergences (see `scoped_window.dart`)**: HMAC dropped →
/// real `note_excerpt`; the `journal_entries.payload.category` axis has
/// no device field, so `category` is always null and an optional
/// `category` filter is *not applied* (a `device_note` says so rather
/// than silently returning wrong rows). The primary drill-down
/// (account_id × window × amount range × limit) is faithful. Mandatory
/// `purpose` + hard caps (≤31d, ≤50) preserved for the AiTrace audit.
library;

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/scoped/scoped_window.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

class ReadAccountWindowTool implements DeviceTool {
  const ReadAccountWindowTool();

  @override
  String get name => 'read_account_window';

  @override
  String get description =>
      'Scoped Detail：返回某账户在指定窗口内的交易明细（drill-down）。'
      '只在用户问「这张卡上花了哪些」需要例证时调用；首选 Snapshot 工具回答聚合性问题。'
      '硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：merchant_hashed + category。'
      'purpose 必填，用于 AiTrace 审计。可选 category / min_amount_minor / max_amount_minor。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['account_id', 'from', 'to', 'purpose'],
    'properties': {
      'account_id': {'type': 'string'},
      'from': {'type': 'string', 'description': 'ISO 起点（包含）'},
      'to': {'type': 'string', 'description': 'ISO 终点（不包含），to - from ≤ 31 天'},
      'purpose': {'type': 'string', 'enum': kScopedPurposes.toList()},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'default': 20},
      'category': {'type': 'string', 'description': '可选；按类目二次过滤'},
      'min_amount_minor': {
        'type': 'integer',
        'description': '可选；最小 signed minor units',
      },
      'max_amount_minor': {
        'type': 'integer',
        'description': '可选；最大 signed minor units',
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
    final accountId = (input['account_id'] is String)
        ? (input['account_id'] as String).trim()
        : null;
    if (accountId == null || accountId.isEmpty) {
      return _bad('account_id required');
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
    final minAmount = input['min_amount_minor'] is num
        ? (input['min_amount_minor'] as num).toInt()
        : null;
    final maxAmount = input['max_amount_minor'] is num
        ? (input['max_amount_minor'] as num).toInt()
        : null;
    final categoryFilter = input['category'] is String
        ? (input['category'] as String).trim()
        : null;

    final entries = await ctx.ref.read(
      journalEntriesWithPostingsStreamProvider.future,
    );
    final accounts = await ctx.ref.read(accountsStreamProvider.future);
    String? accountKind;
    for (final a in accounts) {
      if (a.id == accountId) {
        accountKind = a.type.name;
        break;
      }
    }

    return shape(
      entries,
      accountId: accountId,
      from: from,
      to: to,
      limit: limit,
      purpose: purpose,
      accountKind: accountKind,
      minAmountMinor: minAmount,
      maxAmountMinor: maxAmount,
      categoryFilter: (categoryFilter != null && categoryFilter.isNotEmpty)
          ? categoryFilter
          : null,
    );
  }

  /// Pure port of `account_window::filter_and_sanitise`. One row per
  /// matching posting (`accountId == account`), entry date in
  /// `[from, to)`, optional signed min/max amount, newest-first,
  /// truncated to `limit`. No HMAC; `category` always null (device gap).
  static Map<String, Object?> shape(
    List<JournalEntryWithPostings> entries, {
    required String accountId,
    required DateTime from,
    required DateTime to,
    required int limit,
    required String purpose,
    String? accountKind,
    int? minAmountMinor,
    int? maxAmountMinor,
    String? categoryFilter,
  }) {
    final hits =
        <
          ({
            String id,
            BigInt amount,
            String currency,
            DateTime date,
            String? note,
          })
        >[];
    for (final ewp in entries) {
      final date = ewp.entry.date.toUtc();
      if (date.isBefore(from) || !date.isBefore(to)) continue;
      for (final p in ewp.postings) {
        if (p.accountId != accountId) continue;
        final amount = (p.units * Decimal.fromInt(100)).round().toBigInt();
        if (minAmountMinor != null && amount < BigInt.from(minAmountMinor)) {
          continue;
        }
        if (maxAmountMinor != null && amount > BigInt.from(maxAmountMinor)) {
          continue;
        }
        hits.add((
          id: ewp.entry.id,
          amount: amount,
          currency: p.unit,
          date: date,
          note: ewp.entry.narration.isEmpty ? null : ewp.entry.narration,
        ));
      }
    }
    hits.sort((a, b) => b.date.compareTo(a.date));
    final totalCount = hits.length;
    final shown = hits.take(limit).toList();

    var totalAbs = BigInt.zero;
    String? currencySeen;
    var mixed = false;
    final txns = <Map<String, Object?>>[];
    for (final h in shown) {
      totalAbs += h.amount.abs();
      if (currencySeen == null) {
        currencySeen = h.currency;
      } else if (currencySeen != h.currency) {
        mixed = true;
      }
      txns.add(<String, Object?>{
        'id': h.id,
        'occurred_at': h.date.toIso8601String(),
        'amount_minor': h.amount.toString(),
        'currency': h.currency,
        // §4.6.3: device-direct → no HMAC; real excerpt instead.
        'note_excerpt': h.note == null
            ? null
            : scopedExcerpt(h.note!, kScopedNoteExcerptChars),
        'category': null, // device has no journal-category axis
      });
    }

    final summary = mixed
        ? <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'mixed_currency': true,
            'account_kind': accountKind,
          }
        : <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'total_minor': totalAbs.toString(),
            'currency': currencySeen,
            'account_kind': accountKind,
          };

    return <String, Object?>{
      'summary': summary,
      'transactions': txns,
      'purpose': purpose,
      if (categoryFilter != null)
        'device_note':
            '端侧模式下 journal 没有 category 维度（category 即支出账户），'
            '已忽略 category=$categoryFilter 二次过滤；如需按类目请改用账户/Snapshot 工具。',
    };
  }
}
