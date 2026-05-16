/// `get_cashflow_buckets` — device port (§4.6 W-D4.2c, Snapshot P1).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_cashflow_buckets.rs`; the monthly
/// roll-up is a faithful port of
/// `read_models::cashflow_buckets::aggregate` and the
/// `impls::get_cashflow_buckets` read path (window math + output
/// shape). The backend projects this into a D1 read model; the device
/// recomputes the identical inflow/outflow split straight from the
/// local ledger (`journalEntriesWithPostingsStreamProvider`).
///
/// **§4.6.1 divergences** (ledger is the device truth, no D1 read
/// model): the `freshness` envelope is dropped (same stance as
/// `get_net_worth_summary` / `get_holdings`); `source` is
/// `device_ledger` instead of the backend's literal `read_model`
/// (mirrors the analytical tools' device-specific `source`
/// convention — keeping `read_model` would falsely claim a read model
/// the device doesn't have). Everything else (`from` / `to` /
/// `currency` / `series` rows / `note`) is byte-identical to the cloud
/// tool so the model reads one shape on both runtimes.
///
/// Sibling of `get_net_worth_summary`: same monthly-bucket window math
/// and asset-leg exclusion, the complementary split (this one buckets
/// inflow vs outflow per month·currency; net_worth accumulates the
/// signed net). A shared `snapshot_window` helper is the natural DRY
/// extraction once `compute_net_worth` becomes the third caller
/// (rule-of-three).
library;

import 'package:decimal/decimal.dart';

import '../../../../../data/domain/asset.dart';
import '../../../../../data/repositories/journal_entry_providers.dart';
import '../../../../../data/repositories/journal_entry_repository.dart';
import '../../../../../features/investment/data/providers.dart';
import 'device_tool.dart';

class GetCashflowBucketsTool implements DeviceTool {
  const GetCashflowBucketsTool();

  @override
  String get name => 'get_cashflow_buckets';

  // Verbatim from backend `get_cashflow_buckets.rs` DESCRIPTION
  // (whitespace collapsed). Kept identical cloud↔device for prompt
  // parity; the device just sources the same numbers locally.
  @override
  String get description =>
      '返回最近 N 个月的现金 inflow / outflow 分桶。'
      '数据来自 AI Read Model `cashflow_buckets`（Snapshot 层 P1）—— '
      '月粒度，每月按币种独立累加 inflow (units > 0) 与 outflow (abs(units < 0))，'
      '各自带笔数。与 net_worth_snapshot 互补：本工具回答'
      '「钱从哪来、往哪去」，net_worth 回答「累计净走向」。'
      '典型问题：「上个月主要支出方向」「每月平均收入多少」「这季度有几次大额支出」。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'months_back': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 24,
        'default': 6,
        'description': '返回最近多少个月。默认 6。',
      },
      'currency': {'type': 'string', 'description': '可选；只返回某一币种。默认所有币种。'},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final monthsBack = input['months_back'] is num
        ? (input['months_back'] as num).toInt().clamp(1, 24)
        : 6;
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

  /// Pure port of `cashflow_buckets::aggregate` + the
  /// `impls::get_cashflow_buckets` window/shape. `currency` is the
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

    // (year_month, currency) → [inflow, outflow, inCount, outCount].
    // Device JEs are pre-joined to their postings, so the backend's
    // entry_id→ym map collapses into a single pass; asset legs
    // (unit ∈ asset_ids) and zero-units legs are skipped exactly like
    // `aggregate` (the zero check is on units, not the rounded minor).
    final acc = <String, Map<String, List<BigInt>>>{}; // ym → cur → buckets
    for (final ewp in entries) {
      final ym = _ym(ewp.entry.date.toUtc());
      for (final p in ewp.postings) {
        if (assetIds.contains(p.unit)) continue; // skip asset leg
        if (p.units == Decimal.zero) continue; // skip zero-units leg
        final minor = (p.units * Decimal.fromInt(100)).round().toBigInt();
        final byCur = acc.putIfAbsent(ym, () => <String, List<BigInt>>{});
        final b = byCur.putIfAbsent(
          p.unit,
          () => [BigInt.zero, BigInt.zero, BigInt.zero, BigInt.zero],
        );
        if (minor > BigInt.zero) {
          b[0] += minor;
          b[2] += BigInt.one;
        } else {
          b[1] += -minor;
          b[3] += BigInt.one;
        }
      }
    }

    // Rows sorted by (year_month, currency) — matches `aggregate` +
    // the read query's `ORDER BY year_month, currency`.
    final rows =
        <
          ({
            String ym,
            String currency,
            BigInt inflow,
            BigInt outflow,
            BigInt inCount,
            BigInt outCount,
          })
        >[];
    for (final ymEntry in acc.entries) {
      for (final curEntry in ymEntry.value.entries) {
        final b = curEntry.value;
        rows.add((
          ym: ymEntry.key,
          currency: curEntry.key,
          inflow: b[0],
          outflow: b[1],
          inCount: b[2],
          outCount: b[3],
        ));
      }
    }
    rows.sort((a, b) {
      final c = a.ym.compareTo(b.ym);
      return c != 0 ? c : a.currency.compareTo(b.currency);
    });

    // Window: inclusive [from_ym, to_ym] ending at the current month,
    // verbatim from `impls::get_cashflow_buckets`.
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
      final net = r.inflow - r.outflow;
      series.add(<String, Object?>{
        'year_month': r.ym,
        'currency': r.currency,
        'inflow_minor': r.inflow.toString(),
        'outflow_minor': r.outflow.toString(),
        'net_minor': net.toString(),
        'inflow_count': r.inCount.toInt(),
        'outflow_count': r.outCount.toInt(),
      });
    }

    return <String, Object?>{
      'from': fromYm,
      'to': toYm,
      'currency': currency,
      'series': series,
      // §4.6.1: ledger-direct, no D1 read model → no `freshness`;
      // `source` reflects device provenance, not a read model.
      'source': 'device_ledger',
      'note':
          '月粒度 inflow / outflow 分桶；net_minor = inflow - outflow'
          '（与 net_worth_snapshot.net_flow 同源但形态不同，本工具拆分桶不累计）。',
    };
  }
}
