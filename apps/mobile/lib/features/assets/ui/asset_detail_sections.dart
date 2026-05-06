import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/historical_bar.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../asset_detail_providers.dart';

class AssetSummaryCard extends StatelessWidget {
  const AssetSummaryCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return LiquidGlassCard(
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
            '${asset.market ?? l10n.assetDetailUnknown} · ${asset.currency}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class AssetHoldingCard extends ConsumerWidget {
  const AssetHoldingCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
      error: (e, _) =>
          _ErrorCard(message: l10n.assetDetailHoldingsLoadError('$e')),
      data: (snap) {
        final qty = snap?.quantity ?? Decimal.zero;
        final hasPosition = qty.sign > 0;
        final avgCost = hasPosition
            ? (snap!.costBasisInAssetCurrency / qty).toDecimal(
                scaleOnInfinitePrecision: 8,
              )
            : null;
        final marketValueAsset = snap?.marketValueInAssetCurrency;
        return LiquidGlassCard(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.assetDetailHoldingsTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Spacing.s12),
              _MetricRow(
                label: l10n.assetDetailCurrentQuantity,
                value: hasPosition ? _formatQuantity(qty) : '—',
              ),
              const SizedBox(height: Spacing.s8),
              _MetricRow(
                label: l10n.assetDetailAverageCost,
                trailing: AnimatedMoneyText(
                  amount: avgCost?.toDouble(),
                  currencyCode: asset.currency,
                  fractionDigits: _priceFractionDigits(asset.type),
                ),
              ),
              const SizedBox(height: Spacing.s8),
              _MetricRow(
                label: l10n.assetDetailCurrentMarketValue,
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
                    l10n.assetDetailPriceUnavailable,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class AssetPnLCard extends ConsumerWidget {
  const AssetPnLCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
      return _ErrorCard(
        message: l10n.assetDetailPnLLoadError('${snapshotAsync.error}'),
      );
    }

    final snap = snapshotAsync.value;
    final hasPosition = (snap?.quantity.sign ?? 0) > 0;
    final unrealizedAsset = snap == null
        ? null
        : snap.marketValueInAssetCurrency - snap.costBasisInAssetCurrency;
    final unrealizedPct =
        (snap == null || snap.costBasisInAssetCurrency.sign <= 0)
        ? null
        : (unrealizedAsset! / snap.costBasisInAssetCurrency)
              .toDecimal(scaleOnInfinitePrecision: 6)
              .toDouble();

    final dailyChange = (snap == null || !hasPosition)
        ? null
        : _dailyChangeFromHistory(historyAsync, snap.quantity);

    return LiquidGlassCard(
      padding: Spacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.assetDetailPnLTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.assetDetailUnrealizedPnL,
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
              '${l10n.assetDetailBaseCurrency(snap.baseCurrency)} '
              '${_formatBaseAmount(snap.unrealizedPnlInBase)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const Divider(height: Spacing.s24),
          _MetricRow(
            label: l10n.assetDetailTodayChange,
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

class AssetTrendMiniChartCard extends ConsumerWidget {
  const AssetTrendMiniChartCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketKey = _historyKey(asset);
    final theme = Theme.of(context);
    if (marketKey == null) {
      return LiquidGlassCard(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.assetDetailTrend30d, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.assetDetailNoMarketLinked,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final historyAsync = ref.watch(assetPriceHistoryProvider(marketKey));
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));

    return LiquidGlassCard(
      padding: Spacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.assetDetailTrend30d,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (historyAsync.value?.isStale == true) const _StaleBadge(),
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
    );
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
    final l10n = AppLocalizations.of(context);
    if (!hasPosition || !hasHistory) {
      return Text('—', style: Theme.of(context).textTheme.bodyMedium);
    }
    if (isLoading && value == null) {
      return const SizedBox(
        width: 80,
        child: SkeletonBox(height: 14, radius: Radii.xs),
      );
    }
    if (value == null) {
      return Text(
        isStale ? l10n.assetDetailQuoteStale : l10n.assetDetailQuoteUnavailable,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return DeltaText(value: value!.toDouble(), currencyCode: currency);
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
    final l10n = AppLocalizations.of(context);
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
            l10n.assetDetailTrendLoadError('${history.error}'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final bars = history.value?.data ?? const <HistoricalBar>[];
    if (bars.isEmpty) {
      return const SizedBox(height: 160, child: EmptyChartPlaceholder());
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
      ChartSeries(name: l10n.assetDetailSeriesClosePrice, points: pricePoints),
      if (costBasisAvg != null)
        ChartSeries(
          name: l10n.assetDetailSeriesCostBasis,
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
          xAxis: const TimeAxis(format: AxisDateFormat.dayMonth, maxLabels: 4),
          yAxis: ValueAxis.currency(currencyCode: currency, maxLabels: 4),
          aspectRatio: chartAspectFor(constraints.maxWidth),
          semanticLabel: l10n.assetDetailTrendSemanticLabel,
        ),
      ),
    );
  }
}

class _StaleBadge extends StatelessWidget {
  const _StaleBadge();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        l10n.assetDetailStaleBadge,
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
        trailing ?? Text(value ?? '—', style: theme.textTheme.bodyMedium),
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
    return LiquidGlassCard(
      padding: Spacing.card,
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
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
