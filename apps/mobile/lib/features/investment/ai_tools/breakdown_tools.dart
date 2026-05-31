/// `get_industry_breakdown` / `get_geo_breakdown` /
/// `get_market_cap_breakdown` — device port (Snapshot).
///
/// Verbatim mirror of the backend's structure: one
/// `impls::get_breakdown(ctx, dim)` over a `BreakdownDim` enum with
/// three thin tool wrappers. The backend reuses `get_holdings` then
/// projects the holdings rows joined with asset metadata; the device
/// does exactly that via [GetHoldingsTool.shape] over
/// [devicePortfolioSnapshotProvider] + [allAssetsStreamProvider] —
/// schema/description per backend file verbatim, the projection a
/// faithful port of `get_breakdown` + `dim_label`.
///
/// **§4.6.1**: the backend `attach_inherited` copies `get_holdings`'s
/// `freshness` + `source` onto the result; device `get_holdings` is
/// ledger-direct (no D1 read model) so it carries `source:
/// client_portfolio_snapshot` and **no `freshness`** — the same
/// inheritance, faithfully reflecting device provenance. The backend's
/// `holdings`-absent early return can't occur here (device
/// `get_holdings` always emits a `holdings` object, possibly empty), so
/// an empty portfolio takes the normal path → `total 0.0`, empty
/// `buckets`, full envelope (identical to the backend's empty-holdings
/// normal path).
library;

import 'dart:convert';

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/investment/ai_tools/get_holdings_tool.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

/// Port of `impls::BreakdownDim`.
enum BreakdownDim { industry, region, marketCap }

/// Port of `impls::dim_label`. `industry`/`region` fall back to
/// `unknown` only when the typed field is null (an empty string passes
/// through, matching the backend's `payload_str(...).unwrap_or`);
/// `market_cap` is parsed out of `metadataJson` and is `unknown` on any
/// missing / non-JSON / non-string-field case.
String breakdownDimLabel(Asset asset, BreakdownDim dim) {
  switch (dim) {
    case BreakdownDim.industry:
      return asset.industry ?? 'unknown';
    case BreakdownDim.region:
      return asset.region ?? 'unknown';
    case BreakdownDim.marketCap:
      final raw = asset.metadataJson ?? '';
      try {
        final m = jsonDecode(raw);
        if (m is Map && m['market_cap'] is String) {
          return m['market_cap'] as String;
        }
        return 'unknown';
      } catch (_) {
        return 'unknown';
      }
  }
}

double? _valueNum(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Port of `impls::holding_value_base`: only yields a value when the
/// holding's own `base_currency` equals [base] (case-insensitive).
double? _holdingValueBase(Map<Object?, Object?> h, String key, String base) {
  final hb = h['base_currency'];
  if (hb is! String) return null;
  if (hb.toUpperCase() != base.toUpperCase()) return null;
  return _valueNum(h[key]);
}

/// Pure port of `impls::get_breakdown`. [snapshot] is
/// [devicePortfolioSnapshotProvider]'s value; the holdings projection
/// is taken from [GetHoldingsTool.shape] exactly as the backend reuses
/// `get_holdings`. Cost basis is preferred in the snapshot base
/// currency (else asset-currency cost), aggregated per `dim_label`
/// bucket, `share = cost / total`, buckets sorted by cost descending.
Map<String, Object?> breakdownShape(
  Map<String, Object?>? snapshot, {
  required List<Asset> assets,
  required BreakdownDim dim,
}) {
  final holdingsOut = GetHoldingsTool.shape(snapshot);
  final assetsById = {for (final a in assets) a.id: a};

  final baseRaw = holdingsOut['base_currency'];
  final base = baseRaw is String ? baseRaw.toUpperCase() : null;
  final holdings = (holdingsOut['holdings'] as Map?) ?? const {};

  // label → (cost, currency-first-seen)
  final buckets = <String, ({double cost, String? currency})>{};
  var total = 0.0;
  for (final e in holdings.entries) {
    final assetId = e.key as String;
    final h = e.value;
    if (h is! Map<Object?, Object?>) continue;
    final asset = assetsById[assetId];
    if (asset == null) continue; // backend: asset_lookup miss → skip

    double? c;
    if (base != null) c = _holdingValueBase(h, 'cost_basis_base', base);
    c ??= h['cost_basis'] is num ? (h['cost_basis'] as num).toDouble() : null;
    c ??= _valueNum(h['cost_basis_asset_currency']);
    final cost = c ?? 0.0;

    final String? currency;
    if (base != null) {
      currency = base;
    } else {
      final cc = h['currency'] ?? h['asset_currency'];
      currency = cc is String ? cc : null;
    }

    final label = breakdownDimLabel(asset, dim);
    final prev = buckets[label];
    buckets[label] = (
      cost: (prev?.cost ?? 0.0) + cost,
      currency: prev?.currency ?? currency,
    );
    total += cost;
  }

  final items =
      buckets.entries
          .map(
            (e) => <String, Object?>{
              'label': e.key,
              'cost_basis': e.value.cost,
              'share': total > 0.0 ? e.value.cost / total : 0.0,
              'currency': e.value.currency,
            },
          )
          .toList()
        ..sort(
          (a, b) => (b['cost_basis']! as double).compareTo(
            a['cost_basis']! as double,
          ),
        );

  final out = <String, Object?>{
    'total': total,
    'base_currency': base,
    'buckets': items,
    'approximation': true,
    'note': '占比基于记账成本；有客户端 snapshot base 成本时使用 base 折算，否则使用原币近似。',
  };
  // Port of `attach_inherited`: copy whatever get_holdings exposed.
  // Device get_holdings → source: client_portfolio_snapshot, no
  // freshness (§4.6.1).
  final src = holdingsOut['source'];
  if (src != null) out['source'] = src;
  final fresh = holdingsOut['freshness'];
  if (fresh != null) out['freshness'] = fresh;
  return out;
}

abstract class _BreakdownTool implements DeviceTool {
  const _BreakdownTool();

  BreakdownDim get dim;

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final snapshot = await ctx.ref.read(devicePortfolioSnapshotProvider.future);
    final assets = await ctx.ref.read(allAssetsStreamProvider.future);
    return breakdownShape(snapshot, assets: assets, dim: dim);
  }
}

class GetIndustryBreakdownTool extends _BreakdownTool {
  const GetIndustryBreakdownTool();

  @override
  String get name => 'get_industry_breakdown';

  @override
  BreakdownDim get dim => BreakdownDim.industry;

  // Verbatim from backend `get_industry_breakdown.rs` DESCRIPTION.
  @override
  String get description =>
      '按 asset.industry 分组聚合当前股票/ETF 持仓的记账成本，返回每个行业的占比与币种。';
}

class GetGeoBreakdownTool extends _BreakdownTool {
  const GetGeoBreakdownTool();

  @override
  String get name => 'get_geo_breakdown';

  @override
  BreakdownDim get dim => BreakdownDim.region;

  // Verbatim from backend `get_geo_breakdown.rs` DESCRIPTION.
  @override
  String get description => '按 asset.region 分组聚合当前持仓的记账成本，返回每个地区的占比。';
}

class GetMarketCapBreakdownTool extends _BreakdownTool {
  const GetMarketCapBreakdownTool();

  @override
  String get name => 'get_market_cap_breakdown';

  @override
  BreakdownDim get dim => BreakdownDim.marketCap;

  // Verbatim from backend `get_market_cap_breakdown.rs` DESCRIPTION.
  @override
  String get description =>
      '按市值分类（large/mid/small/unknown）聚合当前股票持仓的记账成本。'
      '分类来自 asset.metadata_json.market_cap，缺失时归入 unknown。';
}
