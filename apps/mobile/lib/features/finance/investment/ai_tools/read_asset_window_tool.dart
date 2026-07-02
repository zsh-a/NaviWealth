/// `read_asset_window` — device port (Scoped Detail).
///
/// Schema + description verbatim from
/// the historical backend `read_asset_window` tool; logic a faithful
/// port of `scoped_detail::asset_window::filter_and_extract`. Returns
/// the asset *legs* (signed `qty_delta` + side + `cost_per_unit` +
/// currency) for postings whose `unit == asset_id` within the window.
/// Naturally desensitised (no merchant) — no HMAC question here. Reads
/// Drift via `journalEntriesWithPostingsStreamProvider` (no D1, no
/// freshness gate — §4.6.1). Mandatory `purpose` + ≤31d / ≤50 caps for
/// the AiTrace audit.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/ai_tools/_shared/scoped/scoped_window.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

class ReadAssetWindowTool implements DeviceTool {
  const ReadAssetWindowTool();

  @override
  String get name => 'read_asset_window';

  @override
  String get description =>
      'Scoped Detail：返回某资产在指定窗口内的交易腿（数量变动 + 单价）。'
      '适合「AAPL 这个月有几次买卖」「这只 ETF 最近调仓」之类的 drill-down。'
      '硬限额：窗口 ≤ 31 天，limit ≤ 50。返回 qty_delta（signed）+ side (buy/sell) + cost_per_unit + currency；'
      '天然脱敏（不含 merchant 信息）。purpose 必填。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['asset_id', 'from', 'to', 'purpose'],
    'properties': {
      'asset_id': {'type': 'string'},
      'from': {'type': 'string'},
      'to': {'type': 'string'},
      'purpose': {'type': 'string', 'enum': kScopedPurposes.toList()},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'default': 20},
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
    final assetId = input['asset_id'] is String
        ? (input['asset_id'] as String).trim()
        : null;
    if (assetId == null || assetId.isEmpty) {
      return _bad('asset_id required');
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

    final entries = await ctx.ref.read(
      journalEntriesWithPostingsStreamProvider.future,
    );
    return shape(
      entries,
      assetId: assetId,
      from: from,
      to: to,
      limit: limit,
      purpose: purpose,
    );
  }

  /// Pure port of `asset_window::filter_and_extract`. One row per
  /// posting whose `unit == assetId`, entry date in `[from, to)`,
  /// non-zero qty, newest-first, truncated to `limit`.
  static Map<String, Object?> shape(
    List<JournalEntryWithPostings> entries, {
    required String assetId,
    required DateTime from,
    required DateTime to,
    required int limit,
    required String purpose,
  }) {
    final hits =
        <
          ({
            String id,
            double qty,
            double? costPerUnit,
            String? currency,
            DateTime date,
          })
        >[];
    for (final ewp in entries) {
      final date = ewp.entry.date.toUtc();
      if (date.isBefore(from) || !date.isBefore(to)) continue;
      for (final p in ewp.postings) {
        if (p.unit != assetId) continue;
        final qty = p.units.toDouble();
        if (qty == 0.0) continue;
        hits.add((
          id: ewp.entry.id,
          qty: qty,
          costPerUnit: (p.cost?.perUnit ?? p.price?.perUnit)?.toDouble(),
          currency: p.cost?.currency ?? p.price?.currency,
          date: date,
        ));
      }
    }
    hits.sort((a, b) => b.date.compareTo(a.date));
    final totalCount = hits.length;
    final shown = hits.take(limit).toList();

    var netQtyDelta = 0.0;
    String? currencySeen;
    var mixed = false;
    final txns = <Map<String, Object?>>[];
    for (final h in shown) {
      netQtyDelta += h.qty;
      if (h.currency != null) {
        if (currencySeen == null) {
          currencySeen = h.currency;
        } else if (currencySeen != h.currency) {
          mixed = true;
        }
      }
      txns.add(<String, Object?>{
        'id': h.id,
        'occurred_at': h.date.toIso8601String(),
        'qty_delta': h.qty,
        'side': h.qty > 0 ? 'buy' : 'sell',
        'cost_per_unit': h.costPerUnit,
        'currency': h.currency,
      });
    }

    final summary = mixed
        ? <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'net_qty_delta': netQtyDelta,
            'mixed_currency': true,
          }
        : <String, Object?>{
            'count': totalCount,
            'returned': txns.length,
            'net_qty_delta': netQtyDelta,
            'currency': currencySeen,
          };

    return <String, Object?>{
      'summary': summary,
      'transactions': txns,
      'purpose': purpose,
    };
  }
}
