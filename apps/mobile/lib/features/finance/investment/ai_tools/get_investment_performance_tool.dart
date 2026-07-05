/// `get_investment_performance` — device port.
///
/// Schema + description verbatim from
/// the historical backend `get_investment_performance` tool. Per
/// §4.3.3 the device `holdingsSnapshotProvider` is the sole computer;
/// the `investment_performance` read model shape is derived from the
/// same device analytical signal. The tool reads the same provider +
/// the shared [holdingSnapshotToUpload] converter (single source) and
/// projects into the read-model row shape — no D1, no freshness gate.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';

class GetInvestmentPerformanceTool implements DeviceTool {
  const GetInvestmentPerformanceTool();

  @override
  String get name => 'get_investment_performance';

  @override
  String get description =>
      '返回 per-asset 当前持仓表现：market_value / cost_basis / unrealized_pnl / weight。'
      '数据来自 AI Read Model `investment_performance`（Analytical P1，device-sourced）—— '
      '端侧 holdingsSnapshotProvider 算出 per-asset 持仓后，本工具按 AnalyticalUpload '
      'shape 输出本地分析信号，AI 不需要再做计算。'
      '每行: asset_id / asset_currency / base_currency / market_value_base / '
      'cost_basis_base / unrealized_pnl_base / weight / holding_days? / as_of。'
      '典型问题：「我现在赚最多的是哪个标的」「AAPL 持仓现值」「未实现盈亏总计」。'
      '端侧运行时当前不广告 XIRR 工具；需要收益解释时使用本工具的 per-asset return 字段。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'base_currency': {
        'type': 'string',
        'description': '可选；只看某一 base currency（一般用户的整个 portfolio 都是同一个）。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final Map<String, HoldingSnapshot> holdings = await ctx.ref.read(
      holdingsSnapshotProvider.future,
    );
    final uploads = [
      for (final snap in holdings.values) holdingSnapshotToUpload(snap),
    ];
    return shape(
      uploads,
      baseCurrency: input['base_currency'] is String
          ? input['base_currency'] as String
          : null,
    );
  }

  /// Pure projection into the backend `get_investment_performance`
  /// envelope + the same `base_currency` filter as the read model
  /// `query_all`. Decimal fields stay strings (precision-safe).
  static Map<String, Object?> shape(
    List<AnalyticalUpload> uploads, {
    String? baseCurrency,
  }) {
    final base = (baseCurrency != null && baseCurrency.trim().isNotEmpty)
        ? baseCurrency.trim().toUpperCase()
        : null;
    final assets = <Map<String, Object?>>[];
    for (final u in uploads) {
      final p = u.payload;
      final rowBase = p['base_currency'] as String?;
      if (base != null && (rowBase?.toUpperCase() ?? '') != base) continue;
      assets.add(<String, Object?>{
        'id': u.id,
        'asset_id': p['asset_id'],
        'asset_currency': p['asset_currency'],
        'base_currency': rowBase,
        'market_value_base': p['market_value_in_base'],
        'cost_basis_base': p['cost_basis_in_base'],
        'unrealized_pnl_base': p['unrealized_pnl_in_base'],
        'weight': p['weight'],
        'holding_days': p['holding_days'],
        'as_of': p['as_of'],
        'payload': p,
      });
    }
    return <String, Object?>{
      'assets': assets,
      'count': assets.length,
      'source': 'device_analytical_read_model',
      'note':
          'device-sourced：端侧 holdingsSnapshotProvider 算出 per-asset 持仓快照后投影。'
          'decimal 字段为字符串避免精度丢失。端侧运行时当前不广告 XIRR 工具。',
    };
  }
}
