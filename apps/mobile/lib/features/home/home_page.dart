import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/format/providers.dart';
import '../../core/sync/providers.dart';
import '../../core/sync/sync_status.dart';
import '../../data/market/sync/price_sync_coordinator.dart';
import '../../data/market/sync/price_sync_providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../cashflow/ui/cashflow_calendar_card.dart';
import '../cashflow/ui/passive_income_card.dart';
import '../settings/ui/ai_privacy_onboarding.dart';
import 'data/dashboard_insights_provider.dart';
import 'data/dashboard_providers.dart';
import 'domain/dashboard_models.dart';
import 'ui/activity_timeline_preview.dart';
import 'ui/ai_insight_feed.dart';
import 'ui/allocation_summary.dart';
import 'ui/currency_mismatch_banner.dart';
import 'ui/home_greeting_header.dart';
import 'ui/trend_card.dart';

final _valuationStatusTickerProvider = StreamProvider.autoDispose<DateTime>((
  ref,
) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 15),
    (_) => DateTime.now(),
  );
});

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
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return FScaffold(
      // The home cockpit owns its hero greeting; we drop the static
      // "Overview" page title in favour of a personalized status line
      // rendered inside [HomeGreetingHeader]. A bare scaffold (no
      // FHeader) keeps the top of the page calm.
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: PageSkeletonShell<DashboardSnapshot>(
          skeleton: const HomeSkeleton(),
          isLoading: snapshotAsync.isLoading && !snapshotAsync.hasValue,
          child: SafeArea(
            bottom: false,
            child: snapshotAsync.when(
              loading: () => const HomeSkeleton(),
              error: (e, st) => _ErrorBody(error: e),
              data: (snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // §5.10.5 — first-launch privacy onboarding sheet.
                  // Renders nothing once the user has confirmed.
                  const AiPrivacyOnboardingMount(),
                  const CurrencyMismatchBanner(),
                  Expanded(child: _DashboardBody(snapshot: snapshot)),
                ],
              ),
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
        final useCockpit = width >= 1024;
        final basePadding = Breakpoints.isMobile(width)
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom + MediaQuery.paddingOf(context).bottom + 16,
        );

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            if (useCockpit)
              AdaptiveContentFrame(
                maxWidth: AdaptiveMaxWidth.dashboard,
                layout: AdaptiveFrameLayout.cockpit,
                padding: padding.copyWith(top: 0),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HomeGreetingHeader(),
                    _NetWorthHeader(snapshot: snapshot),
                  ],
                ),
                primary: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _CashFlowCardsGrid(),
                    const SizedBox(height: 20),
                    AllocationSummary(snapshot: snapshot),
                    const SizedBox(height: 20),
                    const TrendCard(),
                  ],
                ),
                secondary: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (insights.isNotEmpty) ...[
                      AiInsightFeed(insights: insights),
                      const SizedBox(height: 20),
                    ],
                    const ActivityTimelinePreview(),
                  ],
                ),
              )
            else
              AdaptiveContentFrame(
                maxWidth: AdaptiveMaxWidth.narrow,
                padding: padding.copyWith(top: 0),
                primary: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HomeGreetingHeader(),
                    _NetWorthHeader(snapshot: snapshot),
                    const SizedBox(height: 20),
                    const _CashFlowCardsGrid(),
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
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CashFlowCardsGrid extends StatelessWidget {
  const _CashFlowCardsGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 620;
        if (!twoColumns) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PassiveIncomeCard(),
              SizedBox(height: 12),
              CashflowCalendarCard(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PassiveIncomeCard()),
            SizedBox(width: 12),
            Expanded(child: CashflowCalendarCard()),
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
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final hasData = !snapshot.isEmpty;
    final value = hasData ? snapshot.netWorth.amount.toDouble() : null;
    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    return SoftCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 18,
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
          // Assets / liabilities breakdown. Uses the same currency
          // formatting (symbol + grouping) as the hero number and
          // mirrors the Accounts-hub net-worth card, so money reads the
          // same everywhere instead of a raw "123456 (CNY)" string.
          DefaultTextStyle.merge(
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
            child: hasData
                ? Wrap(
                    spacing: 6,
                    children: [
                      Text(
                        '${l10n.dashboardNetWorthAssetsLabel} '
                        '${formatters.currency(snapshot.totalAssets.amount, code: snapshot.baseCurrency)}',
                      ),
                      const Text('·'),
                      Text(
                        '${l10n.dashboardNetWorthLiabilitiesLabel} '
                        '${formatters.currency(snapshot.totalLiabilities.amount, code: snapshot.baseCurrency)}',
                      ),
                    ],
                  )
                : Text(l10n.homeNetWorthSubtitle(snapshot.baseCurrency)),
          ),
          const _ValuationStatusLine(),
        ],
      ),
    );
  }
}

class _ValuationStatusLine extends ConsumerWidget {
  const _ValuationStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now =
        ref.watch(_valuationStatusTickerProvider).value ?? DateTime.now();
    final priceEvent = ref.watch(priceSyncStatusEventStreamProvider).value;
    final syncEvent = ref.watch(syncStatusEventStreamProvider).value;

    final String? label;
    final bool active;
    if (priceEvent?.status == PriceSyncStatus.syncing) {
      label = l10n.dashboardValuationUpdating;
      active = true;
    } else if (syncEvent?.status == SyncStatus.syncing) {
      label = l10n.dashboardLedgerSyncing;
      active = true;
    } else if (_isRecent(now, priceEvent?.lastSuccessAt)) {
      label = l10n.dashboardValuationUpdated;
      active = false;
    } else {
      return const SizedBox.shrink();
    }

    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            const SizedBox(width: 12, height: 12, child: FCircularProgress())
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isRecent(DateTime now, DateTime? timestamp) {
    if (timestamp == null) return false;
    final age = now.difference(timestamp);
    return !age.isNegative && age < const Duration(minutes: 2);
  }
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
              // Sanity guard: even after the XIRR runaway fix, treat any
              // ratio outside ±100 (i.e. ±10000%) as numerically
              // meaningless and fall through to the bounded currency
              // delta. Stops a single bad upstream value from blowing
              // the hero past the screen.
              child: _isSaneRatio(m.ytdChangePct)
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

/// `true` when [ratio] is non-null, finite, and within ±100 (±10000%).
/// Anything outside that band is almost certainly a numerical artifact
/// upstream — the dashboard hero falls through to the bounded
/// currency-delta representation instead.
bool _isSaneRatio(double? ratio) {
  if (ratio == null) return false;
  if (!ratio.isFinite) return false;
  return ratio.abs() < 100;
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
