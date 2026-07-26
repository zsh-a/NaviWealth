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
        child: _WealthHubBody(
          baseCurrency: snapshot.baseCurrency,
          netWorth: snapshot.netWorth.amount,
          totalAssets: snapshot.totalAssets.amount,
          totalLiabilities: snapshot.totalLiabilities.amount,
        ),
      ),
    );
  }
}

class _WealthHubBody extends ConsumerWidget {
  const _WealthHubBody({
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
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    return RefreshIndicator(
      onRefresh: () async {
        final range = ref.read(dashboardTimeRangeProvider);
        ref.invalidate(dashboardSnapshotProvider);
        ref.invalidate(dashboardTrendProvider(range));
        await Future.wait([
          ref.read(dashboardSnapshotProvider.future),
          ref.read(dashboardTrendProvider(range).future),
        ]);
      },
      child: AppAtmosphere(
        child: AppCollapsingScrollHost(
          padding: EdgeInsets.fromLTRB(
            hPad,
            AppSpacing.s4,
            hPad,
            AppSpacing.s0,
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
          body: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellTabContentPadding(
              context,
              left: hPad,
              top: AppSpacing.s8,
              right: hPad,
            ),
            children: [
              AppCollapsingStage(
                child: _BalanceOverview(
                  baseCurrency: baseCurrency,
                  netWorth: netWorth,
                  totalAssets: totalAssets,
                  totalLiabilities: totalLiabilities,
                ),
              ),
              if (totalAssets != Decimal.zero ||
                  totalLiabilities != Decimal.zero) ...[
                const SizedBox(height: AppPageRhythm.module),
                const WealthTrendSection(),
              ],
              const SizedBox(height: AppPageRhythm.module),
              const _WealthDestinations(),
              if (totalAssets == Decimal.zero &&
                  totalLiabilities == Decimal.zero) ...[
                const SizedBox(height: AppPageRhythm.module),
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
              ] else ...[
                const SizedBox(height: AppPageRhythm.section),
                const WealthPerspectiveSection(),
              ],
            ],
          ),
        ),
      ),
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

/// Compact 2×2 destination grid — no settings-style list rows.
class _WealthDestinations extends StatelessWidget {
  const _WealthDestinations();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <_WealthSectionSpec>[
      _WealthSectionSpec(
        icon: FLucideIcons.walletCards,
        title: l10n.wealthAccountsSectionTitle,
        path: FinanceRoutes.wealthAccounts,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.chartLine,
        title: l10n.wealthHoldingsSectionTitle,
        path: FinanceRoutes.wealthPortfolio,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.circleDollarSign,
        title: l10n.dividendCenterTitle,
        path: FinanceRoutes.cashflowDividends,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.landmark,
        title: l10n.wealthLiabilitiesSectionTitle,
        path: FinanceRoutes.wealthLiabilities,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppPageRhythm.row;
        final tileW = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final spec in sections)
              SizedBox(
                width: tileW,
                child: _WealthDestinationTile(spec: spec),
              ),
          ],
        );
      },
    );
  }
}

class _WealthDestinationTile extends StatelessWidget {
  const _WealthDestinationTile({required this.spec});

  final _WealthSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard.raised(
      borderless: true,
      onPress: () => context.push(spec.path),
      padding: AppPageRhythm.densePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(spec.icon, size: AppIconSizes.lg, color: colors.primary),
          const SizedBox(height: AppPageRhythm.row),
          Text(
            spec.title,
            style: context.labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _WealthSectionSpec {
  const _WealthSectionSpec({
    required this.icon,
    required this.title,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String path;
}
