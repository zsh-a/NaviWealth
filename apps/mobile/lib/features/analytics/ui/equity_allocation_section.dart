import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        GlassSectionHeader(
          title: l10n.analyticsEquityTitle,
          subtitle: l10n.analyticsEquitySubtitle,
        ),
        const SizedBox(height: Spacing.s12),
        DimensionSegment(value: dimension, onChanged: onDimensionChanged),
        const SizedBox(height: Spacing.s16),
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
          ? Theme.of(context).colorScheme.outlineVariant
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
        const SizedBox(height: Spacing.s16),
        NwPieChart(
          slices: slices,
          aspectRatio: 1.4,
          drillDown: ChartDrillDown.slice((slice) {
            final bucket = slice.meta as EquityAllocationBucket;
            _openBucketSheet(context, bucket, view.baseCurrency);
          }),
          semanticLabel: l10n.analyticsEquityTitle,
        ),
        const SizedBox(height: Spacing.s16),
        if (view.unclassifiedCount > 0)
          _UnclassifiedBanner(count: view.unclassifiedCount),
        if (view.unclassifiedCount > 0) const SizedBox(height: Spacing.s12),
        LiquidGlassCard(
          layer: GlassLayer.tertiary,
          padding: EdgeInsets.zero,
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
    showGlassModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l10n.analyticsTotalValueLabel(baseCurrency),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        AnimatedMoneyText(
          amount: totalValueInBase.toDouble(),
          currencyCode: baseCurrency,
          style: theme.textTheme.titleLarge,
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final pct = bucket.weight.toDouble();
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        localizeBucketLabel(l10n, bucket),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(
        l10n.analyticsHoldingsCount(bucket.holdings.length),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedMoneyText(
              amount: bucket.totalValueInBase.toDouble(),
              currencyCode: baseCurrency,
              style: theme.textTheme.titleSmall,
              minDeltaThreshold: 0.01,
            ),
            Text(
              formatters.percent(pct, decimalDigits: 1),
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

class _UnclassifiedBanner extends StatelessWidget {
  const _UnclassifiedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s12,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: theme.colorScheme.tertiary),
          const SizedBox(width: Spacing.s8),
          Expanded(child: Text(l10n.analyticsUnclassifiedHint(count))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s32),
      child: Column(
        children: [
          Icon(
            Icons.donut_large_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.s12),
          Text(
            l10n.analyticsEmptyTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.s4),
          Text(
            l10n.analyticsEmptyHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
        SizedBox(height: Spacing.s16),
        SkeletonBox(height: 220, radius: Radii.sm),
        SizedBox(height: Spacing.s16),
        SkeletonBox(height: 56, radius: Radii.sm),
        SizedBox(height: Spacing.s8),
        SkeletonBox(height: 56, radius: Radii.sm),
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s32),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 32),
          const SizedBox(height: Spacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: Spacing.s8),
          AppButton.tertiary(label: l10n.analyticsRetry, onPressed: onRetry),
        ],
      ),
    );
  }
}
