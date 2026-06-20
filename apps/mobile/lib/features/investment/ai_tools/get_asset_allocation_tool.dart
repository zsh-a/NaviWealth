/// `get_asset_allocation` — device port.
///
/// Schema + description verbatim from
/// the historical backend `get_asset_allocation` tool. The backend
/// aggregates the `asset_allocation_snapshot` read model by
/// `(asset_type, currency)`; here we run the **identical aggregation**
/// (port of `asset_allocation_snapshot::aggregate`) over the device
/// holdings the user already has via [devicePortfolioSnapshotProvider]
/// — so no D1 read model, no freshness gate (§4.6.1).
///
/// Cost-basis only and `weight` normalised within each currency, byte
/// for byte like the backend (`weight` is a ratio ⇒ scale-invariant,
/// so the minor-unit rounding here doesn't affect the analytically
/// important field).
library;

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

class GetAssetAllocationTool implements DeviceTool {
  const GetAssetAllocationTool();

  @override
  String get name => 'get_asset_allocation';

  @override
  String get description =>
      '按 asset.type（stock / etf / crypto / cash / ...）+ currency 双键聚合'
      '当前持仓的 cost_basis_minor。数据来自 AI Read Model '
      '`asset_allocation_snapshot`（Snapshot 层 P1，cloud-projected）。'
      'weight 在同 currency 内归一（sum==1 within currency），'
      '跨币种不直接相加（云端没有 FX 源）。'
      '典型问题：「我的股票/加密占比」「USD 仓位最大头是哪类」「股票总成本多少」。'
      '单位是 **成本** 而非市值；市值需配合端侧价格数据计算。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'bucket_dim': {
        'type': 'string',
        'enum': ['asset_type'],
        'default': 'asset_type',
        'description': '桶维度。当前只有 asset_type。预留 industry / region。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final snapshot = await ctx.ref.read(devicePortfolioSnapshotProvider.future);
    return shape(snapshot);
  }

  /// Pure port of `asset_allocation_snapshot::aggregate`.
  static Map<String, Object?> shape(Map<String, Object?>? snapshot) {
    final holdings = (snapshot?['holdings'] as Map?) ?? const {};

    // (bucket_key, currency) → (cost, count)
    final sub = <(String, String), ({Decimal cost, int count})>{};
    for (final raw in holdings.values) {
      if (raw is! Map) continue;
      final bucketKey = (raw['type'] as String?) ?? 'unknown';
      final currency = (raw['asset_currency'] as String?) ?? 'unknown';
      final cost =
          Decimal.tryParse('${raw['cost_basis_asset_currency'] ?? '0'}') ??
          Decimal.zero;
      final key = (bucketKey, currency);
      final prev = sub[key];
      sub[key] = prev == null
          ? (cost: cost, count: 1)
          : (cost: prev.cost + cost, count: prev.count + 1);
    }

    final currencyTotals = <String, Decimal>{};
    sub.forEach((k, v) {
      currencyTotals[k.$2] = (currencyTotals[k.$2] ?? Decimal.zero) + v.cost;
    });

    final hundred = Decimal.fromInt(100);
    final buckets =
        sub.entries.map((e) {
          final (bucketKey, currency) = e.key;
          final denom = currencyTotals[currency] ?? Decimal.zero;
          final weight = denom == Decimal.zero
              ? 0.0
              : (e.value.cost / denom).toDouble();
          return <String, Object?>{
            'bucket_dim': 'asset_type',
            'bucket_key': bucketKey,
            'currency': currency,
            'total_cost_minor': (e.value.cost * hundred)
                .round()
                .toBigInt()
                .toString(),
            'position_count': e.value.count,
            'weight': weight,
          };
        }).toList()..sort((a, b) {
          final byCcy = (a['currency']! as String).compareTo(
            b['currency']! as String,
          );
          if (byCcy != 0) return byCcy;
          return (b['weight']! as double).compareTo(a['weight']! as double);
        });

    return <String, Object?>{
      'buckets': buckets,
      'count': buckets.length,
      'note': 'cost basis（非市值；云端无 FX 源）；weight 在同 currency 内归一。',
    };
  }
}
