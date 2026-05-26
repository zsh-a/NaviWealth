/// `get_holdings` — device port (§4.6 W-D4.2).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_holdings.rs`. The backend tool
/// *prefers* the client `portfolio_snapshot` and short-circuits to it
/// (`source: "client_portfolio_snapshot"`); on device that snapshot is
/// the canonical local truth (holdings engine + FX + multi-lot), so
/// this reproduces exactly that branch via
/// [devicePortfolioSnapshotProvider]. No D1 read model, hence no
/// freshness gate (§4.6.1).
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

class GetHoldingsTool implements DeviceTool {
  const GetHoldingsTool();

  @override
  String get name => 'get_holdings';

  @override
  String get description =>
      '返回当前持仓快照。优先使用客户端 portfolio_snapshot 中的持仓引擎结果；'
      '缺失时从 journal_entries / postings 推导近似值。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'as_of': {'type': 'string', 'description': 'ISO-8601 截止时刻（含），不传则到当前时间。'},
      'base_currency': {
        'type': 'string',
        'description': '希望返回的折算基准币种；snapshot 已带 base 值时会使用。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final snapshot = await ctx.ref.read(devicePortfolioSnapshotProvider.future);
    return shape(
      snapshot,
      inputAsOf: input['as_of'] is String ? input['as_of'] as String : null,
      inputBaseCurrency: input['base_currency'] is String
          ? input['base_currency'] as String
          : null,
    );
  }

  /// Pure mirror of the backend `client_portfolio_snapshot` branch.
  /// `snapshot` is [devicePortfolioSnapshotProvider]'s value (or `null`
  /// when the user has no holdings — still a device-sourced answer,
  /// just empty).
  static Map<String, Object?> shape(
    Map<String, Object?>? snapshot, {
    String? inputAsOf,
    String? inputBaseCurrency,
  }) {
    final snapshotBase = snapshot?['base_currency'] as String?;
    final requestedRaw = inputBaseCurrency ?? snapshotBase;
    final requestedBase =
        (requestedRaw != null && requestedRaw.trim().isNotEmpty)
        ? requestedRaw.trim().toUpperCase()
        : null;
    final asOf =
        inputAsOf ??
        (snapshot?['as_of'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    final holdings = snapshot?['holdings'] ?? <String, Object?>{};

    return <String, Object?>{
      'as_of': asOf,
      'base_currency': requestedBase ?? snapshotBase,
      'snapshot_base_currency': snapshotBase,
      'holdings': holdings,
      'approximation': false,
      'source': 'client_portfolio_snapshot',
      'conversion_source': 'client_portfolio_snapshot',
    };
  }
}
