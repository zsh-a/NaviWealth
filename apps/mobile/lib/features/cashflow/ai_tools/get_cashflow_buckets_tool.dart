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
/// signed net). The broader day/week net-worth computer was cloud-only
/// and is not advertised after W-D7.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

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
  }) => aggregateLegacyCashflowBuckets(
    entries: entries,
    assets: assets,
    monthsBack: monthsBack,
    currency: currency,
    now: now,
  );
}
