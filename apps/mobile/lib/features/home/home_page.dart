import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'data/dashboard_insights_provider.dart';
import 'data/dashboard_providers.dart';
import 'domain/dashboard_models.dart';
import 'ui/activity_timeline_preview.dart';
import 'ui/ai_insight_feed.dart';
import 'ui/allocation_summary.dart';
import 'ui/currency_mismatch_banner.dart';
import 'ui/trend_card.dart';

/// Home cockpit (FIR-52, redesigned).
///
/// One-column scroll: Net Worth Hero → AI Insight Feed → Allocation
/// Summary → Recent Activity preview → Trend chart. The heavy Sankey
/// allocation moved out of the home (it now lives on the dedicated
/// detail surface inside the Accounts hub) so the home reads more like
/// a calm "financial cockpit" than a trading terminal.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.homeAppBarTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.auto_awesome_outlined),
            onPress: () => context.push(AppRoutes.ai),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: PageSkeletonShell<DashboardSnapshot>(
          skeleton: const HomeSkeleton(),
          isLoading: snapshotAsync.isLoading && !snapshotAsync.hasValue,
          child: snapshotAsync.when(
            loading: () => const HomeSkeleton(),
            error: (e, st) => _ErrorBody(error: e),
            data: (snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CurrencyMismatchBanner(),
                Expanded(child: _DashboardBody(snapshot: snapshot)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(dashboardInsightsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = !Breakpoints.isMobile(width);
        final basePadding = isWide
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
        final padding = basePadding.copyWith(
          bottom: basePadding.bottom + MediaQuery.paddingOf(context).bottom + 16,
        );

        // Tablet/desktop: cap content width to 720 so a wide window doesn't
        // stretch lines into uncomfortable spans. The cockpit reads as a
        // focused single column at any width.
        final content = ListView(
          padding: padding,
          children: [
            _NetWorthHeader(snapshot: snapshot),
            if (insights.isNotEmpty) ...[
              const SizedBox(height: 20),
              AiInsightFeed(insights: insights),
            ],
            const SizedBox(height: 20),
            AllocationSummary(snapshot: snapshot),
            const SizedBox(height: 20),
            const ActivityTimelinePreview(),
            const SizedBox(height: 20),
            const TrendCard(),
          ],
        );
        if (isWide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }
}

class _NetWorthHeader extends ConsumerWidget {
  const _NetWorthHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasData = !snapshot.isEmpty;
    final value = hasData ? snapshot.netWorth.amount.toDouble() : null;
    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeNetWorthTitle,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Cap dynamic-text scaling on the 32dp hero number so users on
            // 200% system font size don't blow the card out of its row.
            // FittedBox handles long currency strings (¥123,456,789.00)
            // by scaling glyphs down to fit the card's content rect.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedMoneyText(
                  amount: value,
                  currencyCode: snapshot.baseCurrency,
                  style: TypographyTokens.numericDisplay,
                  showSign: value != null && value < 0,
                ),
              ),
            ),
            if (hasData) ...[
              const SizedBox(height: 8),
              _DeltaMetricsRow(metrics: metricsAsync),
            ],
            const SizedBox(height: 4),
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
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBaseAmount(double v) => v.toStringAsFixed(0);
}

/// Today / MTD / YTD strip rendered under the hero net-worth number.
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
          SkeletonBox(width: 60, height: 14, radius: 4),
          SizedBox(width: 16),
          SkeletonBox(width: 60, height: 14, radius: 4),
          SizedBox(width: 16),
          SkeletonBox(width: 60, height: 14, radius: 4),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (m) {
        return Wrap(
          spacing: 16,
          runSpacing: 4,
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
              child: m.monthlyChangePct == null
                  ? const DeltaChip(value: null)
                  : m.monthlyChangePct!.isFinite
                  ? DeltaChip(
                      value: m.monthlyChangePct! * 100,
                      fractionDigits: 2,
                    )
                  : DeltaText(
                      value: m.monthlyChange.amount.toDouble(),
                      format: DeltaFormat.currency,
                      currencyCode: m.baseCurrency,
                    ),
            ),
            _MetricCell(
              label: l10n.dashboardHeaderDeltaYtdLabel,
              child: m.ytdChangePct != null
                  ? DeltaText.percentFromRatio(
                      ratio: m.ytdChangePct,
                      fractionDigits: 2,
                    )
                  : m.ytdChange.amount.sign != 0
                  ? DeltaText(
                      value: m.ytdChange.amount.toDouble(),
                      format: DeltaFormat.currency,
                      currencyCode: m.baseCurrency,
                    )
                  : DeltaText.percentFromRatio(ratio: null),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: context.theme.typography.xs2.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(width: 4),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          AppLocalizations.of(context).dashboardSnapshotError('$error'),
          textAlign: TextAlign.center,
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.destructive,
          ),
        ),
      ),
    );
  }
}
