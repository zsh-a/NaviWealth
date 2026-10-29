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
import '../../home/domain/dashboard_trend_builder.dart';
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
          label: l10n.wealthActionsTitle,
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
    final baseCurrency = snapshot.baseCurrency;
    final netWorth = snapshot.netWorth.amount;
    final totalAssets = snapshot.totalAssets.amount;
    final totalLiabilities = snapshot.totalLiabilities.amount;
    final isEmpty =
        totalAssets == Decimal.zero && totalLiabilities == Decimal.zero;
    final showValuationTrust =
        !snapshot.isEmpty || snapshot.currencyMismatches.isNotEmpty;
    Widget balanceOverview(BuildContext context, NwScrubState? scrub) {
      final sample = scrub?.point.meta;
      final historical = sample is TrendPoint ? sample : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceOverview(
            baseCurrency: baseCurrency,
            netWorth: historical?.netWorth.amount ?? netWorth,
            totalAssets: historical?.assets.amount ?? totalAssets,
            totalLiabilities:
                historical?.liabilities.amount ?? totalLiabilities,
            asOf: historical?.asOf,
          ),
          if (showValuationTrust)
            Visibility(
              visible: historical == null,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: ValuationTrustNotice(snapshot: snapshot),
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = Breakpoints.isMobile(constraints.maxWidth)
            ? AppSpacing.s16
            : AppSpacing.s24;
        return BriefScaffold(
          maxContentWidth: AdaptiveMaxWidth.page,
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
          stage: AppCollapsingStage(
            child: AdaptiveSupportingPane(
              primary: isEmpty
                  ? balanceOverview(context, null)
                  : WealthTrendSection(overviewBuilder: balanceOverview),
              supporting: const _WealthDestinations(),
            ),
          ),
          stickyBuilder: (context, progress) => AppCollapsedSummaryBar(
            progress: progress,
            child: AppCollapsedSummaryContent(
              label: l10n.homeNetWorthTitle,
              value: MoneyText(
                amount: netWorth.toDouble(),
                currencyCode: baseCurrency,
                compact: true,
                style: context.appTheme.type.numericTitleStrong,
              ),
            ),
          ),
          summaryTiles: staggeredSummaryTiles([
            if (isEmpty)
              AdaptiveSummaryTile(
                role: AdaptiveSummaryTileRole.continuous,
                child: AppEmptyState(
                  icon: FLucideIcons.landmark,
                  title: l10n.wealthEmptyTitle,
                  message: l10n.wealthEmptyBody,
                  action: FButton(
                    onPress: () => context.push(FinanceRoutes.wealthAccountNew),
                    prefix: const Icon(FLucideIcons.plus),
                    child: Text(l10n.wealthEmptyAction),
                  ),
                ),
              ),
            if (!isEmpty)
              const AdaptiveSummaryTile(
                role: AdaptiveSummaryTileRole.continuous,
                child: WealthPerspectiveSection(),
              ),
          ]),
        );
      },
    );
  }
}

class _BalanceOverview extends ConsumerWidget {
  const _BalanceOverview({
    required this.baseCurrency,
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    this.asOf,
  });

  final String baseCurrency;
  final Decimal netWorth;
  final Decimal totalAssets;
  final Decimal totalLiabilities;
  final DateTime? asOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final hidden = AmountPrivacyScope.isHiddenOf(context);
    final label = asOf == null
        ? l10n.homeNetWorthTitle
        : formatters.date(asOf!);
    final amountLabel = hidden
        ? AmountPrivacyScope.hiddenSemanticsLabelOf(context)
        : formatters.currency(netWorth, code: baseCurrency);
    return Padding(
      key: const ValueKey('wealth-balance-overview'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.mutedLabelStyle)),
              Text(
                baseCurrency,
                style: context.captionLabelStyle.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppPageRhythm.row),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: Semantics(
              label: '$label $amountLabel',
              excludeSemantics: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  key: const ValueKey('wealth-balance-value'),
                  emphasizeInteger: true,
                  amount: netWorth.toDouble(),
                  currencyCode: baseCurrency,
                  style: context.appTheme.type.display,
                  showSign: netWorth.toDouble() < 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppPageRhythm.module),
          AppMetricCluster(
            dense: true,
            axis: MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? Axis.vertical
                : Axis.horizontal,
            items: [
              AppMetricItem(
                label: l10n.dashboardNetWorthAssetsLabel,
                value: formatters.currency(totalAssets, code: baseCurrency),
                sensitive: true,
                maxLines: 1,
              ),
              AppMetricItem(
                label: l10n.dashboardNetWorthLiabilitiesLabel,
                value: formatters.currency(
                  totalLiabilities,
                  code: baseCurrency,
                ),
                sensitive: true,
                maxLines: 1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Object navigation for accounts, holdings, watched symbols, and liabilities.
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
        icon: FLucideIcons.star,
        title: l10n.wealthWatchlistSectionTitle,
        subtitle: l10n.wealthWatchlistSectionSubtitle,
        path: FinanceRoutes.wealthWatchlist,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.arrowDownRight,
        title: l10n.wealthLiabilitiesSectionTitle,
        subtitle: l10n.wealthLiabilitiesSectionSubtitle,
        path: FinanceRoutes.wealthLiabilities,
      ),
    ];
    return Column(
      key: const ValueKey('wealth-destinations'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s4,
            bottom: AppSpacing.s8,
          ),
          child: Text(l10n.wealthObjectsTitle, style: context.mutedLabelStyle),
        ),
        Column(
          children: [
            for (var index = 0; index < sections.length; index += 2)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _WealthDestinationRow(spec: sections[index])),
                  Expanded(
                    child: _WealthDestinationRow(spec: sections[index + 1]),
                  ),
                ],
              ),
          ],
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
    return AppNavRow(
      icon: spec.icon,
      title: spec.title,
      semanticsLabel: '${spec.title}, ${spec.subtitle}',
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      showChevron: false,
      onTap: () => context.push(spec.path),
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
