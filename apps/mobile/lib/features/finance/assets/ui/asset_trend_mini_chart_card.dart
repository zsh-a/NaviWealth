import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetTrendMiniChartCard extends ConsumerWidget {
  const AssetTrendMiniChartCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketKey = assetDetailHistoryKey(asset);
    if (marketKey == null) {
      return SoftCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.assetDetailTrend30d,
                style: context.theme.typography.body.sm,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(l10n.assetDetailNoMarketLinked, style: context.captionStyle),
            ],
          ),
        ),
      );
    }

    final historyAsync = ref.watch(assetPriceHistoryProvider(marketKey));
    final snapshotAsync = ref.watch(assetHoldingSnapshotProvider(asset.id));

    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.assetDetailTrend30d,
                    style: context.theme.typography.body.sm,
                  ),
                ),
                if (historyAsync.value?.isStale == true)
                  AppBadge(
                    label: l10n.assetDetailStaleBadge,
                    size: AppBadgeSize.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
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
    final l10n = AppLocalizations.of(context);
    if (history.isLoading && history.value == null) {
      return const SizedBox(
        height: AppChartHeights.standard,
        child: SkeletonBox(height: AppChartHeights.standard, radius: 8),
      );
    }
    if (history.hasError && history.value == null) {
      return SizedBox(
        height: AppChartHeights.standard,
        child: Center(
          child: Text(
            l10n.assetDetailTrendLoadError('${history.error}'),
            style: context.theme.typography.body.xs,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final bars = history.value?.data ?? const <HistoricalBar>[];
    if (bars.isEmpty) {
      return const SizedBox(
        height: AppChartHeights.standard,
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
        height: AppChartHeights.medium,
        child: NwLineChart(
          series: series,
          xAxis: const TimeAxis(format: AxisDateFormat.dayMonth, maxLabels: 4),
          yAxis: ValueAxis.currency(currencyCode: currency, maxLabels: 4),
          aspectRatio: chartAspectFor(constraints.maxWidth),
          interpolation: ChartInterpolation.linear,
          semanticLabel: l10n.assetDetailTrendSemanticLabel,
        ),
      ),
    );
  }
}
