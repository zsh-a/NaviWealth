import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'data/dashboard_providers.dart';
import 'domain/dashboard_models.dart';
import 'ui/allocation_card.dart';
import 'ui/currency_mismatch_banner.dart';
import 'ui/trend_card.dart';

/// Dashboard surface (FIR-52).
///
/// Two cards: a category-allocation pie + drill-down list, and a net-worth
/// trend chart with time-range chips. Layout adapts at the
/// [Breakpoints.mobile] boundary — single column on phones, two-column on
/// tablet / desktop so the cards sit side-by-side.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeAppBarTitle),
        actions: [
          IconButton(
            tooltip: l10n.homeAiAssistantTooltip,
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/ai'),
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const _DashboardSkeleton(),
        error: (e, st) => _ErrorBody(error: e),
        data: (snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CurrencyMismatchBanner(),
            Expanded(child: _DashboardBody(snapshot: snapshot)),
          ],
        ),
      ),
      floatingActionButton: AppFab(
        onPressed: () => context.push('/assets/trade'),
        tooltip: l10n.homeRecordTradeTooltip,
        child: const Icon(Icons.add_chart),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = !Breakpoints.isMobile(width);
        final padding =
            isWide ? Spacing.pageWide : Spacing.pageMobile;
        final header = _NetWorthHeader(snapshot: snapshot);
        final allocation = AllocationCard(snapshot: snapshot);
        final trend = TrendCard(snapshot: snapshot);

        if (isWide) {
          return ListView(
            padding: padding,
            children: [
              header,
              const SizedBox(height: Spacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  const SizedBox(width: Spacing.s16),
                  Expanded(child: trend),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: padding,
          children: [
            header,
            const SizedBox(height: Spacing.s12),
            allocation,
            const SizedBox(height: Spacing.s12),
            trend,
          ],
        );
      },
    );
  }
}

class _NetWorthHeader extends ConsumerWidget {
  const _NetWorthHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasData = !snapshot.isEmpty;
    final value = hasData ? snapshot.netWorth.amount.toDouble() : null;
    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeNetWorthTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s8),
            // Cap dynamic-text scaling on the 32dp hero number so users on
            // 200% system font size don't blow the card out of its row.
            // FittedBox handles the long-currency / many-digits case
            // (e.g. ¥123,456,789.00) by scaling the glyphs down to fit.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  amount: value,
                  currencyCode: snapshot.baseCurrency,
                  style: TypographyTokens.numericDisplay,
                  showSign: value != null && value < 0,
                ),
              ),
            ),
            if (hasData) ...[
              const SizedBox(height: Spacing.s8),
              _DeltaMetricsRow(metrics: metricsAsync),
            ],
            const SizedBox(height: Spacing.s4),
            Text(
              hasData
                  ? l10n.dashboardNetWorthBreakdown(
                      _formatBaseAmount(snapshot.totalAssets.amount.toDouble()),
                      _formatBaseAmount(
                        snapshot.totalLiabilities.amount.toDouble(),
                      ),
                      snapshot.baseCurrency,
                    )
                  : l10n.homeNetWorthSubtitle(snapshot.baseCurrency),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBaseAmount(double v) => v.toStringAsFixed(0);
}

/// Mirrors the layout of [_DashboardBody] with skeleton cards so the page
/// settles into its real content without shuffling. Local-first reads
/// usually flip from loading → data inside ~50ms; a spinner there reads as
/// a flash, while a static skeleton just briefly previews the shape.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        final padding = isWide ? Spacing.pageWide : Spacing.pageMobile;
        const allocation = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18, radius: Radii.xs),
              SizedBox(height: Spacing.s16),
              Center(
                child: SkeletonBox(
                  width: 200,
                  height: 200,
                  radius: Radii.full,
                ),
              ),
              SizedBox(height: Spacing.s16),
              SkeletonBox(height: 14),
              SizedBox(height: Spacing.s8),
              SkeletonBox(height: 14),
            ],
          ),
        );
        const trend = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 18, radius: Radii.xs),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 32, radius: Radii.sm),
              SizedBox(height: Spacing.s12),
              SkeletonBox(height: 220, radius: Radii.sm),
            ],
          ),
        );
        const header = SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 88, height: 14, radius: Radii.xs),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 220, height: 36, radius: Radii.sm),
              SizedBox(height: Spacing.s8),
              SkeletonBox(width: 180, height: 12, radius: Radii.xs),
            ],
          ),
        );
        if (isWide) {
          return ListView(
            padding: padding,
            children: const [
              header,
              SizedBox(height: Spacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  SizedBox(width: Spacing.s16),
                  Expanded(child: trend),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: padding,
          children: const [
            header,
            SizedBox(height: Spacing.s12),
            allocation,
            SizedBox(height: Spacing.s12),
            trend,
          ],
        );
      },
    );
  }
}

/// Today / MTD / YTD strip rendered under the hero net-worth number.
///
/// Uses [DeltaText] for the today figure (currency formatted), [DeltaChip]
/// for the month-to-date percentage (chip styling reads as a "this is the
/// running pulse" badge next to the static breakdown), and another
/// [DeltaText] for YTD return.
class _DeltaMetricsRow extends StatelessWidget {
  const _DeltaMetricsRow({required this.metrics});

  final AsyncValue<DashboardHeaderMetrics> metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return metrics.when(
      loading: () => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: 60, height: 14, radius: Radii.xs),
          SizedBox(width: Spacing.s16),
          SkeletonBox(width: 60, height: 14, radius: Radii.xs),
          SizedBox(width: Spacing.s16),
          SkeletonBox(width: 60, height: 14, radius: Radii.xs),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (m) {
        return Wrap(
          spacing: Spacing.s16,
          runSpacing: Spacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricCell(
              label: l10n.dashboardHeaderDeltaTodayLabel,
              child: DeltaText(
                value: m.dailyChange.amount.toDouble(),
                format: DeltaFormat.currency,
                currencyCode: m.baseCurrency,
              ),
            ),
            _MetricCell(
              label: l10n.dashboardHeaderDeltaMonthLabel,
              child: DeltaChip(
                value: m.monthlyChangePct == null
                    ? null
                    : m.monthlyChangePct! * 100,
                fractionDigits: 2,
              ),
            ),
            _MetricCell(
              label: l10n.dashboardHeaderDeltaYtdLabel,
              child: DeltaText.percentFromRatio(
                ratio: m.ytdChangePct,
                fractionDigits: 2,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Spacing.s4),
        child,
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Text(
          AppLocalizations.of(context).dashboardSnapshotError('$error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}
