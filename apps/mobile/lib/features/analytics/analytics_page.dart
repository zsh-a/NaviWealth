import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/formatters.dart';
import '../../core/format/providers.dart';
import '../../core/haptics/haptics.dart';
import '../../design_system/charts/charts.dart';
import '../../design_system/tokens/breakpoints.dart';
import '../../design_system/tokens/radius_tokens.dart';
import '../../design_system/tokens/spacing_tokens.dart';
import '../../design_system/widgets/responsive_two_column.dart';
import '../../design_system/widgets/skeleton.dart';
import '../../l10n/gen/app_localizations.dart';
import 'data/providers.dart';
import 'domain/equity_allocation.dart';
import 'domain/equity_classification.dart';
import 'ui/benchmark/benchmark_comparison_card.dart';
import 'ui/risk_alert_panel.dart';

/// Analytics tab — currently houses the equity透视 view (FIR-53).
/// Future tabs (returns, liquidity) will be added as additional sections
/// of the same scaffold.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  EquityAllocationDimension _dimension = EquityAllocationDimension.sector;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(equityAllocationViewProvider(_dimension));
    final equityColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: l10n.analyticsEquityTitle,
          subtitle: l10n.analyticsEquitySubtitle,
        ),
        const SizedBox(height: Spacing.s12),
        DimensionSegment(
          value: _dimension,
          onChanged: (d) => setState(() => _dimension = d),
        ),
        const SizedBox(height: Spacing.s16),
        view.when(
          data: (data) => EquityAllocationContent(view: data),
          loading: () => const _LoadingState(),
          error: (e, _) => _ErrorState(
            message: l10n.analyticsLoadError,
            onRetry: () => ref.invalidate(
              equityAllocationViewProvider(_dimension),
            ),
          ),
        ),
      ],
    );
    const riskColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskAlertPanel(),
        SizedBox(height: Spacing.s24),
        BenchmarkComparisonCard(),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analyticsAppBarTitle)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !Breakpoints.isMobile(constraints.maxWidth);
          return ListView(
            padding: isWide ? Spacing.pageWide : Spacing.pageMobile,
            children: [
              ResponsiveTwoColumn(left: equityColumn, right: riskColumn),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: Spacing.s4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Three-way picker for the active allocation dimension. Lifted to the
/// top of the file so widget tests can drive it without reaching into the
/// page state.
class DimensionSegment extends StatelessWidget {
  const DimensionSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EquityAllocationDimension value;
  final ValueChanged<EquityAllocationDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<EquityAllocationDimension>(
      segments: [
        ButtonSegment(
          value: EquityAllocationDimension.sector,
          icon: const Icon(Icons.category_outlined),
          label: Text(l10n.analyticsDimensionSector),
        ),
        ButtonSegment(
          value: EquityAllocationDimension.region,
          icon: const Icon(Icons.public),
          label: Text(l10n.analyticsDimensionRegion),
        ),
        ButtonSegment(
          value: EquityAllocationDimension.marketCap,
          icon: const Icon(Icons.bar_chart),
          label: Text(l10n.analyticsDimensionMarketCap),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) {
        Haptics.selection();
        onChanged(s.first);
      },
      showSelectedIcon: false,
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
      slices.add(Slice(
        label: localizeBucketLabel(l10n, bucket),
        value: bucket.totalValueInBase.toDouble(),
        colorOverride: color,
        meta: bucket,
      ));
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
        if (view.unclassifiedCount > 0)
          const SizedBox(height: Spacing.s12),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final bucket in view.buckets)
                _BucketRow(
                  bucket: bucket,
                  color: colorByKey[bucket.key]!,
                  formatters: formatters,
                  baseCurrency: view.baseCurrency,
                  onTap: () => _openBucketSheet(
                    context,
                    bucket,
                    view.baseCurrency,
                  ),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EquityBucketHoldingsSheet(
        bucket: bucket,
        baseCurrency: baseCurrency,
      ),
    );
  }
}

class _TotalsRow extends ConsumerWidget {
  const _TotalsRow({
    required this.baseCurrency,
    required this.totalValueInBase,
  });

  final String baseCurrency;
  final Decimal totalValueInBase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
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
        Text(
          formatters.currency(totalValueInBase, code: baseCurrency),
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
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
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
            Text(
              formatters.currency(bucket.totalValueInBase, code: baseCurrency),
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

/// Banner that surfaces the count of holdings missing classification
/// metadata. The drill-down to fix them is the unclassified bucket row in
/// the breakdown table immediately below — no separate action needed.
class _UnclassifiedBanner extends StatelessWidget {
  const _UnclassifiedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: theme.colorScheme.tertiary,
          ),
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
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 32,
          ),
          const SizedBox(height: Spacing.s8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: Spacing.s8),
          TextButton(onPressed: onRetry, child: Text(l10n.analyticsRetry)),
        ],
      ),
    );
  }
}

/// Bottom sheet listing the holdings inside a bucket. Tapping a row jumps
/// to the existing asset detail route.
class EquityBucketHoldingsSheet extends ConsumerWidget {
  const EquityBucketHoldingsSheet({
    super.key,
    required this.bucket,
    required this.baseCurrency,
  });

  final EquityAllocationBucket bucket;
  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          0,
          Spacing.s16,
          Spacing.s16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.analyticsBucketSheetTitle(
                localizeBucketLabel(l10n, bucket),
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.analyticsHoldingsCount(bucket.holdings.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (bucket.isUnclassified) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                l10n.analyticsUnclassifiedRowCta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: Spacing.s12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: bucket.holdings.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final h = bucket.holdings[index];
                  return ListTile(
                    title: Text(h.name ?? h.symbol),
                    subtitle: Text(h.symbol),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          formatters.currency(
                            h.marketValueInBase,
                            code: baseCurrency,
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          formatters.percent(
                            h.weight.toDouble(),
                            decimalDigits: 1,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.goNamed(
                        'asset-detail',
                        pathParameters: {'assetId': h.assetId},
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a bucket's stable label key (e.g. `cnA`, `large`, raw sector) to a
/// localized string. Free-form sector names flow through unchanged so a
/// MarketDataService fill of `"Information Technology"` displays as-is in
/// English but as the same string in Chinese (translation of arbitrary
/// industry strings is out of scope).
String localizeBucketLabel(
  AppLocalizations l10n,
  EquityAllocationBucket bucket,
) {
  if (bucket.isUnclassified) return l10n.analyticsBucketUnclassified;
  switch (bucket.dimension) {
    case EquityAllocationDimension.sector:
      return bucket.label;
    case EquityAllocationDimension.region:
      switch (bucket.label) {
        case 'cnA':
          return l10n.analyticsBucketRegionCnA;
        case 'hkStock':
          return l10n.analyticsBucketRegionHk;
        case 'usStock':
          return l10n.analyticsBucketRegionUs;
        case 'crypto':
          return l10n.analyticsBucketRegionCrypto;
        case 'fx':
          return l10n.analyticsBucketRegionFx;
        default:
          return l10n.analyticsBucketRegionUnknown;
      }
    case EquityAllocationDimension.marketCap:
      switch (bucket.label) {
        case 'large':
          return l10n.analyticsBucketMarketCapLarge;
        case 'mid':
          return l10n.analyticsBucketMarketCapMid;
        case 'small':
          return l10n.analyticsBucketMarketCapSmall;
        default:
          return bucket.label;
      }
  }
}
