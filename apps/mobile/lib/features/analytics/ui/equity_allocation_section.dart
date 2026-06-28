import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/equity_allocation.dart';
import '../domain/equity_classification.dart';
import 'dimension_segment.dart';
import 'equity_bucket_sheet.dart';

class AnalyticsEquityColumn extends ConsumerWidget {
  const AnalyticsEquityColumn({
    super.key,
    required this.dimension,
    required this.onDimensionChanged,
  });

  final EquityAllocationDimension dimension;
  final ValueChanged<EquityAllocationDimension> onDimensionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(equityAllocationViewProvider(dimension));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.analyticsEquityTitle,
          subtitle: l10n.analyticsEquitySubtitle,
        ),
        const SizedBox(height: AppSpacing.s12),
        DimensionSegment(value: dimension, onChanged: onDimensionChanged),
        const SizedBox(height: AppSpacing.s16),
        PageSkeletonShell<EquityAllocationView>(
          skeleton: const _LoadingState(),
          isLoading: view.isLoading,
          child: view.when(
            data: (data) => EquityAllocationContent(view: data),
            loading: () => const _LoadingState(),
            error: (e, _) => _ErrorState(
              message: l10n.analyticsLoadError,
              onRetry: () =>
                  ref.invalidate(equityAllocationViewProvider(dimension)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pie + breakdown table + unclassified hint. Public so widget tests can
/// supply a fixed [EquityAllocationView] without going through providers.
class EquityAllocationContent extends ConsumerWidget {
  const EquityAllocationContent({super.key, required this.view});

  final EquityAllocationView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.isEmpty) {
      return const _EmptyState();
    }
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );

    final slices = <Slice>[];
    final colorByKey = <BucketKey, Color>{};
    for (var i = 0; i < view.buckets.length; i++) {
      final bucket = view.buckets[i];
      final color = bucket.isUnclassified
          ? context.theme.colors.border
          : palette.accentAt(i);
      colorByKey[bucket.key] = color;
      slices.add(
        Slice(
          label: localizeBucketLabel(l10n, bucket),
          value: bucket.totalValueInBase.toDouble(),
          colorOverride: color,
          meta: bucket,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalsRow(
          baseCurrency: view.baseCurrency,
          totalValueInBase: view.totalValueInBase,
        ),
        const SizedBox(height: AppSpacing.s16),
        NwPieChart(
          slices: slices,
          aspectRatio: 1.4,
          drillDown: ChartDrillDown.slice((slice) {
            final bucket = slice.meta as EquityAllocationBucket;
            _openBucketSheet(context, bucket, view.baseCurrency);
          }),
          semanticLabel: l10n.analyticsEquityTitle,
        ),
        const SizedBox(height: AppSpacing.s16),
        if (view.unclassifiedCount > 0)
          AppStatusBanner(
            kind: AppStatusKind.warning,
            message: l10n.analyticsUnclassifiedHint(view.unclassifiedCount),
            compact: true,
          ),
        if (view.unclassifiedCount > 0) const SizedBox(height: AppSpacing.s12),
        SoftCard(
          child: Column(
            children: [
              for (final bucket in view.buckets)
                _BucketRow(
                  bucket: bucket,
                  color: colorByKey[bucket.key]!,
                  formatters: formatters,
                  baseCurrency: view.baseCurrency,
                  onTap: () =>
                      _openBucketSheet(context, bucket, view.baseCurrency),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _openBucketSheet(
    BuildContext context,
    EquityAllocationBucket bucket,
    String baseCurrency,
  ) {
    showAppFormSheet<void>(
      context: context,
      builder: (_) =>
          EquityBucketHoldingsSheet(bucket: bucket, baseCurrency: baseCurrency),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.baseCurrency,
    required this.totalValueInBase,
  });

  final String baseCurrency;
  final Decimal totalValueInBase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l10n.analyticsTotalValueLabel(baseCurrency),
          style: context.bodyCaptionStyle,
        ),
        AnimatedMoneyText(
          amount: totalValueInBase.toDouble(),
          currencyCode: baseCurrency,
          style: context.theme.typography.body.lg,
        ),
      ],
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.color,
    required this.formatters,
    required this.baseCurrency,
    required this.onTap,
  });

  final EquityAllocationBucket bucket;
  final Color color;
  final AppFormatters formatters;
  final String baseCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pct = bucket.weight.toDouble();
    return FTile(
      title: Text(
        localizeBucketLabel(l10n, bucket),
        style: context.theme.typography.body.md,
      ),
      prefix: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      subtitle: Text(
        l10n.analyticsHoldingsCount(bucket.holdings.length),
        style: context.captionStyle,
      ),
      suffix: SizedBox(
        width: AppControlWidths.detailLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedMoneyText(
              amount: bucket.totalValueInBase.toDouble(),
              currencyCode: baseCurrency,
              style: context.theme.typography.body.sm,
              minDeltaThreshold: 0.01,
            ),
            Text(
              formatters.percent(pct, decimalDigits: 1),
              style: context.captionStyle,
            ),
          ],
        ),
      ),
      onPress: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.chartPie,
      title: l10n.analyticsEmptyTitle,
      message: l10n.analyticsEmptyHint,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonBox(width: 120, height: 14),
            SkeletonBox(width: 120, height: 18),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 220, radius: 8),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: 56, radius: 8),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(height: 56, radius: 8),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        children: [
          Icon(
            FLucideIcons.circleAlert,
            color: context.theme.colors.destructive,
            size: AppIconSizes.xl,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRetry,
            child: Text(l10n.analyticsRetry),
          ),
        ],
      ),
    );
  }
}
