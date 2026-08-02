import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';

import '../../../../core/format/providers.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../core/shell/shell_visibility.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import '../../home/domain/dashboard_models.dart';
import '../../home/ui/currency_mismatch_banner.dart';
import 'wealth_action_panel.dart';
import 'wealth_perspective_section.dart';
import 'wealth_trend_section.dart';

/// Wealth hub — landing page for the Wealth tab (IA contract §1).
///
/// Renders a Net Worth Hero, compact owned-object navigation, and allocation.
///
/// Boundary rule: Wealth holds *current state of owned things*. Decision
/// surfaces (FIRE, rebalance, income strategy) live on the Plan hub.
class WealthHubPage extends ConsumerWidget {
  const WealthHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ShellTabScaffold(
      title: l10n.wealthHubTitle,
      childPad: false,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.accountsActionsTitle,
          onPress: () => showWealthActionPanel(context),
        ),
      ],
      child: const ShellTabPause(
        routePath: FinanceRoutes.wealth,
        placeholder: WealthHubSkeleton(),
        child: _WealthLiveBody(),
      ),
    );
  }
}

class _WealthLiveBody extends ConsumerWidget {
  const _WealthLiveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return snapshotAsync.when(
      loading: () => const PageSkeletonShell<Object>(
        isLoading: true,
        skeleton: WealthHubSkeleton(),
        child: SizedBox.shrink(),
      ),
      error: (e, st) => kDefaultError(
        context,
        e,
        st,
        onRetry: () => ref.invalidate(dashboardSnapshotProvider),
      ),
      data: (snapshot) => PageSkeletonShell<Object>(
        isLoading: false,
        skeleton: const WealthHubSkeleton(),
        child: _WealthHubBody(snapshot: snapshot),
      ),
    );
  }
}

class _WealthHubBody extends ConsumerWidget {
  const _WealthHubBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    final baseCurrency = snapshot.baseCurrency;
    final netWorth = snapshot.netWorth.amount;
    final totalAssets = snapshot.totalAssets.amount;
    final totalLiabilities = snapshot.totalLiabilities.amount;
    final isEmpty =
        totalAssets == Decimal.zero && totalLiabilities == Decimal.zero;
    // The shared cross-domain brief shell (blueprint §8.1) — this page used
    // to hand-assemble the identical refresh/atmosphere/collapse stack.
    return BriefScaffold(
      padding: shellTabContentPadding(
        context,
        left: hPad,
        top: AppSpacing.s8,
        right: hPad,
      ),
      onRefresh: () async {
        final range = ref.read(dashboardTimeRangeProvider);
        ref.invalidate(dashboardSnapshotProvider);
        ref.invalidate(dashboardTrendProvider(range));
        await Future.wait([
          ref.read(dashboardSnapshotProvider.future),
          ref.read(dashboardTrendProvider(range).future),
        ]);
      },
      greeting: const SizedBox.shrink(),
      stage: AppCollapsingStage(
        child: _BalanceOverview(
          baseCurrency: baseCurrency,
          netWorth: netWorth,
          totalAssets: totalAssets,
          totalLiabilities: totalLiabilities,
        ),
      ),
      stickyBuilder: (context, progress) => AppCollapsedSummaryBar(
        progress: progress,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.homeNetWorthTitle,
                style: context.mutedLabelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MoneyText(
              amount: netWorth.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
              style: TypographyTokens.numericTitleStrong,
            ),
          ],
        ),
      ),
      modules: [
        ValuationTrustNotice(snapshot: snapshot),
        const _WealthDestinations(),
        if (!isEmpty) const WealthTrendSection(),
        if (isEmpty)
          AppEmptyState(
            icon: FLucideIcons.landmark,
            title: l10n.wealthEmptyTitle,
            message: l10n.wealthEmptyBody,
            action: FButton(
              onPress: () => context.push(FinanceRoutes.wealthAccountNew),
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.wealthEmptyAction),
            ),
          ),
      ],
      secondary: [if (!isEmpty) const WealthPerspectiveSection()],
    );
  }
}

class _BalanceOverview extends ConsumerWidget {
  const _BalanceOverview({
    required this.baseCurrency,
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
  });

  final String baseCurrency;
  final Decimal netWorth;
  final Decimal totalAssets;
  final Decimal totalLiabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    // Wealth is an analytical workspace, so its balance summary sits directly
    // on the canvas and lets the trend card own visual emphasis. Today keeps
    // the tappable net-worth hero for quick status and navigation.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s8,
      ),
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
              AppBadge(
                label: baseCurrency,
                size: AppBadgeSize.compact,
                tone: AppBadgeTone.accent,
              ),
            ],
          ),
          const SizedBox(height: AppPageRhythm.row),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: Semantics(
              label:
                  '${l10n.homeNetWorthTitle} '
                  '${formatters.currency(netWorth, code: baseCurrency)}',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedMoneyText(
                  amount: netWorth.toDouble(),
                  currencyCode: baseCurrency,
                  style: TypographyTokens.displayLarge,
                  showSign: netWorth.toDouble() < 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppPageRhythm.module),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.dashboardNetWorthAssetsLabel,
                value: formatters.currency(totalAssets, code: baseCurrency),
                maxLines: 1,
              ),
              AppMetricItem(
                label: l10n.dashboardNetWorthLiabilitiesLabel,
                value: formatters.currency(
                  totalLiabilities,
                  code: baseCurrency,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact object navigation. The page exposes only the three things that
/// belong to the balance sheet; income generated by holdings stays inside the
/// portfolio workspace instead of competing as a fourth top-level object.
class _WealthDestinations extends StatelessWidget {
  const _WealthDestinations();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <_WealthSectionSpec>[
      _WealthSectionSpec(
        icon: FLucideIcons.walletCards,
        title: l10n.wealthAccountsSectionTitle,
        subtitle: l10n.wealthAccountsSectionSubtitle,
        path: FinanceRoutes.wealthAccounts,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.chartLine,
        title: l10n.wealthHoldingsSectionTitle,
        subtitle: l10n.wealthHoldingsSectionSubtitle,
        path: FinanceRoutes.wealthPortfolio,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.arrowDownRight,
        title: l10n.wealthLiabilitiesSectionTitle,
        subtitle: l10n.wealthLiabilitiesSectionSubtitle,
        path: FinanceRoutes.wealthLiabilities,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s4,
            bottom: AppSpacing.s8,
          ),
          child: Text(l10n.wealthObjectsTitle, style: context.mutedLabelStyle),
        ),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < sections.length; index++) ...[
                _WealthDestinationRow(spec: sections[index]),
                if (index != sections.length - 1)
                  const AppGroupedDivider(indent: AppSpacing.s56),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WealthDestinationRow extends StatelessWidget {
  const _WealthDestinationRow({required this.spec});

  final _WealthSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: '${spec.title}, ${spec.subtitle}',
      child: ExcludeSemantics(
        child: AppTappable(
          onPress: () => context.push(spec.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14,
              vertical: AppSpacing.s12,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: AppSpacing.s40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: AppOpacity.whisper,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      spec.icon,
                      size: AppIconSizes.md,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.title, style: context.labelStyle),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        spec.subtitle,
                        style: context.captionStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.h18,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WealthSectionSpec {
  const _WealthSectionSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
}
