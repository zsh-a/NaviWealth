/// `get_net_worth_summary` — device port (Snapshot P0).
///
/// Schema + description verbatim from
/// the historical backend `get_net_worth_summary` tool; the monthly
/// roll-up is a faithful port of
/// `read_models::net_worth_snapshot::aggregate` and the
/// `impls::get_net_worth_summary` read path (window math + output
/// shape). The backend projects this into a D1 read model and serves it
/// with a `freshness` envelope; the device recomputes the same monthly
/// net-cash-flow cumulative straight from the local ledger
/// (`journalEntriesWithPostingsStreamProvider`) — the ledger *is* the
/// truth, so there is **no D1 read model and no `freshness` field**
/// (§4.6.1, same stance as `get_holdings`). Everything else (`from` /
/// `to` / `currency` / `series` rows / `note`) matches the original
/// backend tool shape so the model reads one stable contract.
///
/// This is the monthly net-flow view currently available to the device
/// runtime. The broader day/week net-worth computer was a cloud-only
/// tool and is not advertised.
library;

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';

class GetNetWorthSummaryTool implements DeviceTool {
  const GetNetWorthSummaryTool();

  @override
  String get name => 'get_net_worth_summary';

  // Verbatim from backend `get_net_worth_summary.rs` DESCRIPTION
  // (whitespace collapsed). Kept identical cloud↔device for prompt
  // parity; the device just sources the same numbers locally.
  @override
  String get description =>
      '返回最近 N 个月的净现金流累计（月度净资产快照）。'
      '数据来自 AI Read Model `net_worth_snapshot`（Snapshot 层 P0）—— 月粒度，'
      '每月按币种独立累积。当前端侧工具不提供 day/week 粒度，也不减负债 / 不算资产市值。'
      '适合场景：「最近半年净现金流趋势」「上半年现金净流入多少」等月度问题。'
      '需要更细粒度时请基于此月度序列解释限制，不要调用未广告工具。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'months_back': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 60,
        'default': 12,
        'description': '返回最近多少个月。默认 12。',
      },
      'currency': {'type': 'string', 'description': '可选；只返回某一币种。默认返回所有币种。'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final monthsBack = input['months_back'] is num
        ? (input['months_back'] as num).toInt().clamp(1, 60)
        : 12;
    final currencyRaw = input['currency'] is String
        ? (input['currency'] as String).trim().toUpperCase()
        : null;
    final currency = (currencyRaw != null && currencyRaw.isNotEmpty)
        ? currencyRaw
        : null;

    final entries = await ctx.ref.read(
      journalEntriesWithPostingsStreamProvider.future,
    );
    final assets = await ctx.ref.read(allAssetsStreamProvider.future);

    return shape(
      entries,
      assets: assets,
      monthsBack: monthsBack,
      currency: currency,
    );
  }

  static String _ym(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}';

  /// Pure port of `net_worth_snapshot::aggregate` + the
  /// `impls::get_net_worth_summary` window/shape. `currency` is the
  /// already-trimmed-uppercased filter (or null = all). `now` defaults
  /// to the current UTC instant (injectable for deterministic tests,
  /// mirroring the backend's `Utc::now()`).
  static Map<String, Object?> shape(
    List<JournalEntryWithPostings> entries, {
    required List<Asset> assets,
    required int monthsBack,
    String? currency,
    DateTime? now,
  }) {
    final assetIds = {for (final a in assets) a.id};

    // 1+2. (year_month, currency) → net_flow_minor. Device JEs are
    // pre-joined to their postings, so the backend's entry_id→ym map
    // collapses into a single pass; asset legs (unit ∈ asset_ids) are
    // skipped exactly like `aggregate`.
    final flows = <String, Map<String, BigInt>>{}; // ym → currency → minor
    for (final ewp in entries) {
      final ym = _ym(ewp.entry.date.toUtc());
      for (final p in ewp.postings) {
        if (assetIds.contains(p.unit)) continue; // skip asset leg
        final minor = (p.units * Decimal.fromInt(100)).round().toBigInt();
        final byCur = flows.putIfAbsent(ym, () => <String, BigInt>{});
        byCur[p.unit] = (byCur[p.unit] ?? BigInt.zero) + minor;
      }
    }

    // 3. per-currency cumulative (ym ascending), then sort rows by
    // (year_month, currency) — matches `aggregate` + the read query's
    // `ORDER BY year_month, currency`.
    final byCurrency = <String, List<({String ym, BigInt net})>>{};
    for (final ymEntry in flows.entries) {
      for (final curEntry in ymEntry.value.entries) {
        byCurrency.putIfAbsent(curEntry.key, () => []).add((
          ym: ymEntry.key,
          net: curEntry.value,
        ));
      }
    }
    final rows = <({String ym, String currency, BigInt cum, BigInt net})>[];
    for (final entry in byCurrency.entries) {
      final series = entry.value..sort((a, b) => a.ym.compareTo(b.ym));
      var running = BigInt.zero;
      for (final s in series) {
        running += s.net;
        rows.add((ym: s.ym, currency: entry.key, cum: running, net: s.net));
      }
    }
    rows.sort((a, b) {
      final c = a.ym.compareTo(b.ym);
      return c != 0 ? c : a.currency.compareTo(b.currency);
    });

    // Window: inclusive [from_ym, to_ym] ending at the current month,
    // verbatim from `impls::get_net_worth_summary`.
    final nowUtc = (now ?? DateTime.now()).toUtc();
    final toYm = _ym(nowUtc);
    var fromY = nowUtc.year;
    var fromM = nowUtc.month - (monthsBack - 1);
    while (fromM < 1) {
      fromM += 12;
      fromY -= 1;
    }
    final fromYm =
        '${fromY.toString().padLeft(4, '0')}-'
        '${fromM.toString().padLeft(2, '0')}';

    // query_range: year_month in [from_ym, to_ym] (lexicographic ==
    // chronological for zero-padded YYYY-MM) + optional exact currency.
    final series = <Map<String, Object?>>[];
    for (final r in rows) {
      if (r.ym.compareTo(fromYm) < 0 || r.ym.compareTo(toYm) > 0) continue;
      if (currency != null && r.currency != currency) continue;
      series.add(<String, Object?>{
        'year_month': r.ym,
        'currency': r.currency,
        'cumulative_minor': r.cum.toString(),
        'net_flow_minor': r.net.toString(),
      });
    }

    return <String, Object?>{
      'from': fromYm,
      'to': toYm,
      'currency': currency,
      'series': series,
      // §4.6.1: ledger-direct, no D1 read model → no `freshness`.
      'note': '月粒度；不减负债，不算资产市值。端侧运行时当前不广告 day/week 净资产工具。',
    };
  }
}
