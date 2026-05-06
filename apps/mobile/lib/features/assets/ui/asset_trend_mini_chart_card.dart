import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/historical_bar.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetTrendMiniChartCard extends ConsumerWidget {
  const AssetTrendMiniChartCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketKey = assetDetailHistoryKey(asset);
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
