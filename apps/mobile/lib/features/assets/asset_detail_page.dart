import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/market/market_data_providers.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../domain/entities/historical_bar.dart';
import '../../domain/entities/symbol_info.dart';
import '../../domain/services/market_data_service.dart';
import '../../domain/values/asset_market.dart';
import '../investment/domain/models/holding_snapshot.dart';
import 'asset_detail_providers.dart';
import 'cash_form_page.dart';
import 'deposit_form_page.dart';
import 'wealth_product_form_page.dart';

/// Resolves an asset id to the type-specific edit form.
///
/// Centralising the dispatch keeps the route table flat — the router
/// doesn't need to know which sub-form belongs to which AssetType, and
/// adding new manual-valuation flavours later means changing only this
/// switch.
class AssetDetailPage extends ConsumerWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(manualAssetRepositoryProvider);
    return repoAsync.when(
      loading: () => const Scaffold(body: AssetDetailSkeleton()),
      error: (e, _) => Scaffold(body: Center(child: Text('加载失败：$e'))),
      data: (repo) {
        return FutureBuilder<Asset?>(
          future: repo.findById(assetId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(body: AssetDetailSkeleton());
            }
            final asset = snap.data;
            if (asset == null) {
              return const Scaffold(body: Center(child: Text('资产不存在或已删除')));
            }
            return switch (asset.type) {
              AssetType.cash => CashFormPage(assetId: asset.id),
              AssetType.bankDepositTerm ||
              AssetType.bankDepositDemand => DepositFormPage(assetId: asset.id),
              AssetType.wealthProduct => WealthProductFormPage(
                assetId: asset.id,
              ),
              AssetType.stock ||
              AssetType.etf ||
              AssetType.crypto ||
              AssetType.mutualFund =>
                _EquityAssetDetailPage(assetId: asset.id),
              _ => Scaffold(
                appBar: GlassAppBar(title: Text(asset.name ?? asset.symbol)),
                body: const Center(child: Text('该资产类型暂不支持手动编辑')),
              ),
            };
          },
        );
      },
    );
  }
}

/// Detail view for equity-type assets — renders a holding card, a P&L card,
/// a 30-day mini price chart and the FIR-78 "同步元数据" enrichment shortcut.
///
/// Watches the repository (rather than holding the [Asset] passed in)
/// so a successful enrichment immediately reflects in the rendered card
/// without a full route round-trip.
class _EquityAssetDetailPage extends ConsumerStatefulWidget {
  const _EquityAssetDetailPage({required this.assetId});

  final String assetId;

  @override
  ConsumerState<_EquityAssetDetailPage> createState() =>
      _EquityAssetDetailPageState();
}

class _EquityAssetDetailPageState
    extends ConsumerState<_EquityAssetDetailPage> {
  Future<Asset?>? _assetFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repoFuture = ref.read(securitiesAssetRepositoryProvider.future);
    _assetFuture = repoFuture.then((repo) => repo.findById(widget.assetId));
  }

  Future<void> _syncMetadata(Asset asset) async {
    setState(() => _syncing = true);
    try {
      final market = await ref.read(marketDataServiceProvider.future);
      final assetMarket = assetMarketFromWire(asset.market);
      final response = await market.searchSymbol(
        asset.symbol,
        market: (assetMarket == null || assetMarket == AssetMarket.unknown)
            ? null
            : assetMarket,
      );
      final SymbolInfo? best = _pickBest(response.data, asset);
      if (best == null) {
        if (!mounted) return;
        AppMessenger.show(context, ToastKind.error, '未找到匹配的元数据');
        return;
      }

      final repo = await ref.read(securitiesAssetRepositoryProvider.future);
      final before = asset;
      await repo.enrichMetadata(
        id: asset.id,
        name: best.name.isEmpty ? null : best.name,
      );
      if (!mounted) return;

      final filledName = before.name == null && best.name.isNotEmpty;
      AppMessenger.show(context, ToastKind.success, filledName ? '已补全元数据' : '元数据已是最新');
      setState(_reload);
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.error, '网络不可用，无法同步元数据');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Pick the result whose `(market, symbol)` matches the asset (case
  /// insensitive on symbol). Falls back to a symbol-only match, then to
  /// the first hit. Anything weaker than that risks importing the wrong
  /// company under the same ticker (e.g. AAPL on ASX vs NASDAQ).
  SymbolInfo? _pickBest(List<SymbolInfo> hits, Asset asset) {
    if (hits.isEmpty) return null;
    final wantSymbol = asset.symbol.toUpperCase();
    final wantMarket = assetMarketFromWire(asset.market);
    for (final h in hits) {
      if (h.symbol.toUpperCase() == wantSymbol && h.market == wantMarket) {
        return h;
      }
    }
    for (final h in hits) {
      if (h.symbol.toUpperCase() == wantSymbol) return h;
    }
    return hits.first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Asset?>(
      future: _assetFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final asset = snap.data;
        if (asset == null) {
          return const Scaffold(body: Center(child: Text('资产不存在或已删除')));
        }
        return Scaffold(
          appBar: GlassAppBar(
            title: OptionalHero(
              tag: 'asset-${asset.id}-name',
              child: Text(asset.name ?? asset.symbol),
            ),
            actions: [
              IconButton(
                key: const Key('asset-detail-sync-metadata'),
                tooltip: '同步元数据',
                onPressed: _syncing ? null : () => _syncMetadata(asset),
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Spacing.s16),
            children: [
              _AssetSummaryCard(asset: asset),
              const SizedBox(height: Spacing.s12),
              _HoldingCard(asset: asset),
              const SizedBox(height: Spacing.s12),
              _PnLCard(asset: asset),
              const SizedBox(height: Spacing.s12),
              _TrendMiniChartCard(asset: asset),
              const SizedBox(height: Spacing.s16),
              AppButton.primary(
                icon: Icons.add,
                label: '新交易',
                onPressed: () =>
                    context.push('/activity/trade?assetId=${asset.id}'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssetSummaryCard extends StatelessWidget {
  const _AssetSummaryCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(asset.symbol, style: theme.textTheme.titleMedium),
            if (asset.name != null) ...[
              const SizedBox(height: Spacing.s4),
              Text(asset.name!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Spacing.s8),
            Text(
              '${asset.market ?? "未知"} · ${asset.currency}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantity / average cost / market value, all in the asset's own currency
/// per the FIR-48 snapshot. Base-currency totals are rendered on the P&L
/// card alongside unrealized gain.
class _HoldingCard extends ConsumerWidget {
  const _HoldingCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));
    final theme = Theme.of(context);
    return snapshotAsync.when(
      loading: () => const SkeletonCard(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80, height: 14, radius: Radii.xs),
            SizedBox(height: Spacing.s12),
            SkeletonBox(height: 18),
            SizedBox(height: Spacing.s8),
            SkeletonBox(height: 18),
          ],
        ),
      ),
      error: (e, _) => _ErrorCard(message: '持仓加载失败：$e'),
      data: (snap) {
        final qty = snap?.quantity ?? Decimal.zero;
        final hasPosition = qty.sign > 0;
        final avgCost = hasPosition
            ? (snap!.costBasisInAssetCurrency / qty)
                .toDecimal(scaleOnInfinitePrecision: 8)
            : null;
        final marketValueAsset = snap?.marketValueInAssetCurrency;
        return Card(
          child: Padding(
            padding: Spacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('持仓', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.s12),
                _MetricRow(
                  label: '当前数量',
                  value: hasPosition ? _formatQuantity(qty) : '—',
                ),
                const SizedBox(height: Spacing.s8),
                _MetricRow(
                  label: '平均成本',
                  trailing: AnimatedMoneyText(
                    amount: avgCost?.toDouble(),
                    currencyCode: asset.currency,
                    fractionDigits: _priceFractionDigits(asset.type),
                  ),
                ),
                const SizedBox(height: Spacing.s8),
                _MetricRow(
                  label: '当前市值',
                  trailing: OptionalHero(
                    tag: 'asset-${asset.id}-value',
                    child: AnimatedMoneyText(
                      amount: marketValueAsset?.toDouble(),
                      currencyCode: asset.currency,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                if (snap != null && snap.marketValueInAssetCurrency.sign == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s8),
                    child: Text(
                      '价格暂不可用，市值显示为零',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Unrealized P&L (amount + %) and the current day's price-driven change.
/// Realized P&L will come from the postings read model once that
/// projection lands.
class _PnLCard extends ConsumerWidget {
  const _PnLCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));
    final marketKey = _historyKey(asset);
    final historyAsync = marketKey == null
        ? null
        : ref.watch(assetPriceHistoryProvider(marketKey));
    final theme = Theme.of(context);

    if (snapshotAsync.isLoading) {
      return const SkeletonCard(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80, height: 14, radius: Radii.xs),
            SizedBox(height: Spacing.s12),
            SkeletonBox(height: 22),
            SizedBox(height: Spacing.s8),
            SkeletonBox(height: 14),
            SizedBox(height: Spacing.s8),
            SkeletonBox(height: 14),
          ],
        ),
      );
    }
    if (snapshotAsync.hasError) {
      return _ErrorCard(message: '盈亏加载失败：${snapshotAsync.error}');
    }

    final snap = snapshotAsync.value;
    final hasPosition = (snap?.quantity.sign ?? 0) > 0;
    final unrealizedAsset = snap == null
        ? null
        : snap.marketValueInAssetCurrency - snap.costBasisInAssetCurrency;
    final unrealizedPct = (snap == null ||
            snap.costBasisInAssetCurrency.sign <= 0)
        ? null
        : (unrealizedAsset! / snap.costBasisInAssetCurrency)
            .toDecimal(scaleOnInfinitePrecision: 6)
            .toDouble();

    final dailyChange = (snap == null || !hasPosition)
        ? null
        : _dailyChangeFromHistory(historyAsync, snap.quantity);

    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('盈亏', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '未实现盈亏',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.s4),
                      DeltaText(
                        value: unrealizedAsset?.toDouble(),
                        currencyCode: asset.currency,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                DeltaChip(
                  value: unrealizedPct == null ? null : unrealizedPct * 100,
                  fractionDigits: 2,
                ),
              ],
            ),
            if (snap != null) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                '基础货币：${snap.baseCurrency} '
                '${_formatBaseAmount(snap.unrealizedPnlInBase)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Divider(height: Spacing.s24),
            _MetricRow(
              label: '今日变动',
              trailing: _DailyChangeView(
                value: dailyChange,
                currency: asset.currency,
                isLoading: historyAsync?.isLoading ?? false,
                isStale: historyAsync?.value?.isStale ?? false,
                hasHistory: marketKey != null,
                hasPosition: hasPosition,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBaseAmount(Decimal amount) {
    final sign = amount.sign;
    final fmt = NumberFormat.decimalPatternDigits(decimalDigits: 2);
    final formatted = fmt.format(amount.abs().toDouble());
    if (sign < 0) return '-$formatted';
    if (sign > 0) return '+$formatted';
    return formatted;
  }
}

class _DailyChangeView extends StatelessWidget {
  const _DailyChangeView({
    required this.value,
    required this.currency,
    required this.isLoading,
    required this.isStale,
    required this.hasHistory,
    required this.hasPosition,
  });

  final Decimal? value;
  final String currency;
  final bool isLoading;
  final bool isStale;
  final bool hasHistory;
  final bool hasPosition;

  @override
  Widget build(BuildContext context) {
    if (!hasPosition || !hasHistory) {
      return Text(
        '—',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    if (isLoading && value == null) {
      return const SizedBox(
        width: 80,
        child: SkeletonBox(height: 14, radius: Radii.xs),
      );
    }
    if (value == null) {
      return Text(
        isStale ? '行情滞后' : '行情不可用',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return DeltaText(value: value!.toDouble(), currencyCode: currency);
  }
}

/// 30-day close price chart with the user's average-cost basis as a dashed
/// reference line. Price comes from MarketDataService; the cost basis line
/// is computed from the FIR-48 snapshot in asset currency so the two
/// series share an axis.
class _TrendMiniChartCard extends ConsumerWidget {
  const _TrendMiniChartCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketKey = _historyKey(asset);
    final theme = Theme.of(context);
    if (marketKey == null) {
      return Card(
        child: Padding(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('近 30 日走势', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.s8),
              Text(
                '该资产暂未关联市场，无走势可显示',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final historyAsync = ref.watch(assetPriceHistoryProvider(marketKey));
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));

    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('近 30 日走势', style: theme.textTheme.titleSmall),
                ),
                if (historyAsync.value?.isStale == true)
                  _StaleBadge(),
              ],
            ),
            const SizedBox(height: Spacing.s12),
            _ChartBody(
              history: historyAsync,
              snapshot: snapshotAsync.value,
              currency: asset.currency,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.history,
    required this.snapshot,
    required this.currency,
  });

  final AsyncValue<MarketResponse<List<HistoricalBar>>> history;
  final HoldingSnapshot? snapshot;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (history.isLoading && history.value == null) {
      return const SizedBox(
        height: 160,
        child: SkeletonBox(height: 160, radius: Radii.sm),
      );
    }
    if (history.hasError && history.value == null) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            '无法获取行情：${history.error}',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final bars = history.value?.data ?? const <HistoricalBar>[];
    if (bars.isEmpty) {
      return const SizedBox(
        height: 160,
        child: EmptyChartPlaceholder(),
      );
    }

    final pricePoints = [
      for (final b in bars)
        ChartPoint(
          x: b.asOf.millisecondsSinceEpoch.toDouble(),
          y: b.close.toDouble(),
        ),
    ];
    final qty = snapshot?.quantity ?? Decimal.zero;
    final costBasisAvg = (qty.sign > 0)
        ? (snapshot!.costBasisInAssetCurrency / qty)
            .toDecimal(scaleOnInfinitePrecision: 8)
            .toDouble()
        : null;
    final series = <ChartSeries>[
      ChartSeries(
        name: '收盘价',
        points: pricePoints,
      ),
      if (costBasisAvg != null)
        ChartSeries(
          name: '成本基准',
          intent: SeriesIntent.muted,
          emphasis: SeriesEmphasis.dashed,
          points: [
            ChartPoint(x: pricePoints.first.x, y: costBasisAvg),
            ChartPoint(x: pricePoints.last.x, y: costBasisAvg),
          ],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 180,
        child: NwLineChart(
          series: series,
          xAxis: const TimeAxis(
            format: AxisDateFormat.dayMonth,
            maxLabels: 4,
          ),
          yAxis: ValueAxis.currency(currencyCode: currency, maxLabels: 4),
          aspectRatio: chartAspectFor(constraints.maxWidth),
          semanticLabel: '近 30 日收盘价走势',
        ),
      ),
    );
  }
}

class _StaleBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.brSm,
      ),
      child: Text(
        '行情滞后',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing ??
            Text(
              value ?? '—',
              style: theme.textTheme.bodyMedium,
            ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

PriceHistoryKey? _historyKey(Asset asset) {
  final market = assetMarketFromWire(asset.market);
  if (market == null || market == AssetMarket.unknown) return null;
  return PriceHistoryKey(symbol: asset.symbol, market: market, days: 30);
}

Decimal? _dailyChangeFromHistory(
  AsyncValue<MarketResponse<List<HistoricalBar>>>? historyAsync,
  Decimal quantity,
) {
  final bars = historyAsync?.value?.data;
  if (bars == null || bars.length < 2) return null;
  final last = bars[bars.length - 1].close;
  final prev = bars[bars.length - 2].close;
  return (last - prev) * quantity;
}

String _formatQuantity(Decimal qty) {
  final fmt = NumberFormat.decimalPatternDigits(decimalDigits: 4);
  // Trim trailing zeros so whole-share counts read cleanly.
  final raw = fmt.format(qty.toDouble());
  if (!raw.contains('.')) return raw;
  return raw.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

int _priceFractionDigits(AssetType type) {
  switch (type) {
    case AssetType.crypto:
      return 6;
    case AssetType.stock:
    case AssetType.etf:
    case AssetType.mutualFund:
    case AssetType.bond:
      return 2;
    default:
      return 2;
  }
}
