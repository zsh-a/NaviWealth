import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/asset_detail_providers.dart';
import 'asset_detail_common.dart';

class AssetTrendMiniChartCard extends ConsumerWidget {
  const AssetTrendMiniChartCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marketKey = assetDetailHistoryKey(asset);
    if (marketKey == null) {
      return SoftCard.raised(
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

    return SoftCard.raised(
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
            userSafeErrorMessage(
              context,
              history.error!,
              stackTrace: history.stackTrace,
              operation: 'load asset trend',
            ),
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
    final showCostBasis =
        costBasisAvg != null &&
        _costBasisKeepsPriceTrendReadable(pricePoints, costBasisAvg);
    final firstPrice = pricePoints.first.y;
    final periodReturn = firstPrice == 0
        ? null
        : (pricePoints.last.y - firstPrice) / firstPrice.abs();
    final series = <ChartSeries>[
      ChartSeries(name: l10n.assetDetailSeriesClosePrice, points: pricePoints),
      if (showCostBasis)
        ChartSeries(
          name: l10n.assetDetailSeriesCostBasis,
          intent: SeriesIntent.muted,
          emphasis: SeriesEmphasis.dashed,
          fillOpacity: AppOpacity.transparent,
          strokeWidth: AppStroke.medium,
          points: [
            ChartPoint(x: pricePoints.first.x, y: costBasisAvg),
            ChartPoint(x: pricePoints.last.x, y: costBasisAvg),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.assetDetailSeriesClosePrice,
                style: context.microCaptionStyle,
              ),
            ),
            if (periodReturn != null)
              DeltaText.percentFromRatio(
                ratio: periodReturn,
                fractionDigits: 2,
                style: context.captionLabelStyle,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: AppChartHeights.standard,
            child: NwLineChart(
              series: series,
              xAxis: const TimeAxis(
                format: AxisDateFormat.dayMonth,
                maxLabels: 3,
              ),
              yAxis: ValueAxis.currency(
                currencyCode: currency,
                maxLabels: 3,
                showGrid: true,
              ),
              aspectRatio: chartAspectFor(constraints.maxWidth),
              interpolation: ChartInterpolation.linear,
              showDots: false,
              heroDots: !showCostBasis,
              showTouchXAxisLabel: true,
              filled: true,
              semanticLabel: l10n.assetDetailTrendSemanticLabel,
            ),
          ),
        ),
        if (showCostBasis) ...[
          const SizedBox(height: AppSpacing.s8),
          _CostBasisLegend(value: costBasisAvg, currency: currency),
        ],
      ],
    );
  }
}

bool _costBasisKeepsPriceTrendReadable(
  List<ChartPoint> pricePoints,
  double costBasis,
) {
  var minPrice = double.infinity;
  var maxPrice = double.negativeInfinity;
  for (final point in pricePoints) {
    minPrice = math.min(minPrice, point.y);
    maxPrice = math.max(maxPrice, point.y);
  }

  final midpoint = (minPrice + maxPrice) / 2;
  final naturalSpan = math.max(
    maxPrice - minPrice,
    math.max(midpoint.abs() * 0.01, 1),
  );
  final combinedSpan =
      math.max(maxPrice, costBasis) - math.min(minPrice, costBasis);

  // A reference line is useful only while the observed price movement still
  // owns a meaningful share of the plot. Very distant cost bases remain in
  // the holding card instead of flattening the market trend into a hairline.
  return combinedSpan <= naturalSpan * 3;
}

class _CostBasisLegend extends StatelessWidget {
  const _CostBasisLegend({required this.value, required this.currency});

  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final color = context.theme.colors.mutedForeground.withValues(
      alpha: AppOpacity.prominent,
    );
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: AppSpacing.s20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: AppSpacing.s4,
                  height: AppStroke.medium,
                  color: color,
                ),
            ],
          ),
        ),
        Text(l10n.assetDetailSeriesCostBasis, style: context.microCaptionStyle),
        MoneyText(
          amount: value,
          currencyCode: currency,
          style: context.microCaptionStyle,
        ),
      ],
    );
  }
}
