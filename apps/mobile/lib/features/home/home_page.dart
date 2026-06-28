import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/async/deferred_provider_snapshot.dart';
import '../../core/format/providers.dart';
import '../../core/sync/providers.dart';
import '../../core/sync/sync_status.dart';
import '../../design_system/design_system.dart';
import '../../features/finance/data/market/sync/price_sync_coordinator.dart';
import '../../features/finance/data/market/sync/price_sync_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../cashflow/data/recurring_transaction_providers.dart';
import '../cashflow/ui/cashflow_calendar_card.dart';
import '../cashflow/ui/passive_income_card.dart';
import '../settings/ui/ai_privacy_onboarding.dart';
import 'data/dashboard_insights_provider.dart';
import 'data/dashboard_providers.dart';
import 'domain/dashboard_models.dart';
import 'domain/insight_models.dart';
import 'ui/activity_timeline_preview.dart';
import 'ui/ai_insight_feed.dart';
import 'ui/allocation_summary.dart';
import 'ui/currency_mismatch_banner.dart';
import 'ui/home_greeting_header.dart';
import 'ui/home_section.dart';
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

final _financeAmountsHiddenProvider = StateProvider<bool>((ref) => false);

/// Home cockpit.
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
    final today = DateTime.now().toUtc();
    ref.watch(
      recurringMaterialiseDueProvider(
        DateTime.utc(today.year, today.month, today.day),
      ),
    );
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return AppCanvasScaffold(
      // The home cockpit owns its hero greeting; we drop the static
      // "Overview" page title in favour of a personalized status line
      // rendered inside [HomeGreetingHeader]. A bare scaffold (no
      // FHeader) keeps the top of the page calm.
      childPad: false,
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
                CurrencyMismatchNotice(
                  mismatches: snapshot.currencyMismatches,
                  baseCurrency: snapshot.baseCurrency,
                ),
                Expanded(child: _DashboardBody(snapshot: snapshot)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DeferredProviderSnapshot<List<InsightItem>>(
      provider: dashboardInsightsProvider,
      initialValue: const <InsightItem>[],
      builder: (context, insights) =>
          _DashboardBodyContent(snapshot: snapshot, insights: insights),
    );
  }
}

class _DashboardBodyContent extends ConsumerWidget {
  const _DashboardBodyContent({required this.snapshot, required this.insights});

  final DashboardSnapshot snapshot;
  final List<InsightItem> insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amountsHidden = ref.watch(_financeAmountsHiddenProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final useCockpit = width >= Breakpoints.contentTwoColumn;
        final basePadding = Breakpoints.isMobile(width)
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s16,
              )
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s24,
              );
        final padding = basePadding.copyWith(
          bottom:
              basePadding.bottom +
              MediaQuery.paddingOf(context).bottom +
              AppSpacing.s16,
        );

        return AmountPrivacyScope(
          hidden: amountsHidden,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardSnapshotProvider);
              ref.invalidate(dashboardHeaderMetricsProvider);
              await ref.read(dashboardSnapshotProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                        HomeGreetingHeader(insightCount: insights.length),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        const _HomeQuickActions(),
                      ],
                    ),
                    primary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AllocationSummary(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s20),
                        const _CashFlowCardsGrid(),
                        const SizedBox(height: AppSpacing.s20),
                        const TrendCard(),
                      ],
                    ),
                    secondary: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (insights.isNotEmpty) ...[
                          AiInsightFeed(insights: insights),
                          const SizedBox(height: AppSpacing.s20),
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
                        HomeGreetingHeader(insightCount: insights.length),
                        _NetWorthHeader(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s12),
                        const _HomeQuickActions(),
                        if (insights.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s20),
                          AiInsightFeed(insights: insights),
                        ],
                        const SizedBox(height: AppSpacing.s20),
                        AllocationSummary(snapshot: snapshot),
                        const SizedBox(height: AppSpacing.s20),
                        const _CashFlowCardsGrid(),
                        const SizedBox(height: AppSpacing.s20),
                        const TrendCard(),
                        const SizedBox(height: AppSpacing.s20),
                        const ActivityTimelinePreview(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return HomeSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.walletCards,
              label: l10n.homeQuickAddAccount,
              onPress: () => context.push(AppRoutes.wealthAccountNew),
            ),
          ),
          _QuickActionDivider(color: colors.border),
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.receiptText,
              label: l10n.homeQuickRecordEntry,
              onPress: () => context.push(AppRoutes.expenseNew),
            ),
          ),
          _QuickActionDivider(color: colors.border),
          Expanded(
            child: _HomeQuickAction(
              icon: FLucideIcons.upload,
              label: l10n.homeQuickImport,
              onPress: () => context.push(AppRoutes.activityIngest),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeQuickAction extends StatelessWidget {
  const _HomeQuickAction({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.sm, color: colors.primary),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.captionLabelStyle.copyWith(
                  color: colors.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionDivider extends StatelessWidget {
  const _QuickActionDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppStroke.hairline,
      height: AppSpacing.s24,
      color: color.withValues(alpha: AppOpacity.faint),
    );
  }
}

class _CashFlowCardsGrid extends StatelessWidget {
  const _CashFlowCardsGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= Breakpoints.mobile;
        if (!twoColumns) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PassiveIncomeCard(),
              SizedBox(height: AppSpacing.s12),
              CashflowCalendarCard(),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PassiveIncomeCard()),
            SizedBox(width: AppSpacing.s12),
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
    final amountsHidden = ref.watch(_financeAmountsHiddenProvider);
    final privacyLabel = amountsHidden
        ? l10n.financePrivacyShowAmountsTooltip
        : l10n.financePrivacyHideAmountsTooltip;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      borderRadius: AppRadius.xlg,
      borderless: true,
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeNetWorthTitle,
                  style: context.mutedLabelStyle,
                ),
              ),
              Semantics(
                button: true,
                label: privacyLabel,
                child: FTooltip(
                  tipBuilder: (_, _) => Text(privacyLabel),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () {
                      ref.read(_financeAmountsHiddenProvider.notifier).state =
                          !amountsHidden;
                    },
                    child: Icon(
                      amountsHidden ? FLucideIcons.eyeClosed : FLucideIcons.eye,
                      size: AppIconSizes.md,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          // Cap dynamic-text scaling on the 32dp hero number so users on
          // 200% system font size don't blow the card out of its row.
          // FittedBox handles long currency strings (¥123,456,789.00)
          // by scaling glyphs down to fit the card's content rect.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Semantics(
              label: amountsHidden
                  ? '${l10n.homeNetWorthTitle} ${AmountPrivacyScope.hiddenSemanticsLabelOf(context)}'
                  : '${l10n.homeNetWorthTitle} ${formatters.currency(snapshot.netWorth.amount, code: snapshot.baseCurrency)}',
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
          ),
          if (hasData) ...[
            const SizedBox(height: AppSpacing.s8),
            _DeltaMetricsRow(metrics: metricsAsync),
          ],
          const SizedBox(height: AppSpacing.s4),
          // Assets / liabilities breakdown. Uses the same currency
          // formatting (symbol + grouping) as the hero number and
          // mirrors the Accounts-hub net-worth card, so money reads the
          // same everywhere instead of a raw "123456 (CNY)" string.
          DefaultTextStyle.merge(
            style: context.captionStyle,
            child: hasData
                ? Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _NetWorthBreakdownItem(
                        label: l10n.dashboardNetWorthAssetsLabel,
                        amount: snapshot.totalAssets.amount.toDouble(),
                        currencyCode: snapshot.baseCurrency,
                      ),
                      const Text('·'),
                      _NetWorthBreakdownItem(
                        label: l10n.dashboardNetWorthLiabilitiesLabel,
                        amount: snapshot.totalLiabilities.amount.toDouble(),
                        currencyCode: snapshot.baseCurrency,
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

class _NetWorthBreakdownItem extends StatelessWidget {
  const _NetWorthBreakdownItem({
    required this.label,
    required this.amount,
    required this.currencyCode,
  });

  final String label;
  final double amount;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label),
        const SizedBox(width: AppSpacing.s4),
        MoneyText(
          amount: amount,
          currencyCode: currencyCode,
          compact: true,
          fractionDigits: 0,
          style: context.captionStyle,
        ),
      ],
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
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            const SizedBox(
              width: AppSpacing.s12,
              height: AppSpacing.s12,
              child: FCircularProgress(),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(child: Text(label, style: context.captionMediumStyle)),
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
          SizedBox(width: AppSpacing.s16),
          SkeletonBox(width: 60, height: 14, radius: 4),
          SizedBox(width: AppSpacing.s16),
          SkeletonBox(width: 60, height: 14, radius: 4),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (m) {
        return Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s4,
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
        Text(label, style: context.microCaptionStyle),
        const SizedBox(width: AppSpacing.s4),
        child,
      ],
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState.error(
      title: l10n.dashboardSnapshotError('$error'),
      action: AppQuietButton(
        label: l10n.commonRetry,
        onPress: () => ref.invalidate(dashboardSnapshotProvider),
        prefix: const Icon(FLucideIcons.refreshCw, size: AppIconSizes.sm),
      ),
    );
  }
}
