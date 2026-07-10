import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';

import '../../../../core/format/providers.dart';
import '../../../../core/shell/shell_chrome.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../composition/finance_route_paths.dart';
import 'wealth_action_panel.dart';
import 'wealth_perspective_section.dart';

/// Wealth hub — landing page for the Wealth tab (IA contract §1).
///
/// Renders a Net Worth Hero + section grid that links to each owned-object
/// surface that is currently backed by a real workflow: Accounts, Holdings
/// (portfolio), Watchlist, and Liabilities. Phase C replaced the bare ListView
/// that lived under
/// `accounts_master.dart` with this hub.
///
/// Boundary rule: Wealth holds *current state of owned things*. Decision
/// surfaces (FIRE, rebalance, income strategy) live on the Plan hub.
class WealthHubPage extends ConsumerWidget {
  const WealthHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);

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
      child: snapshotAsync.when(
        loading: () => const PageSkeletonShell<Object>(
          isLoading: true,
          skeleton: WealthHubSkeleton(),
          child: SizedBox.shrink(),
        ),
        error: (_, _) => Center(
          child: AppEmptyState.error(
            title: l10n.commonLoadFailed,
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () {
                ref.invalidate(dashboardSnapshotProvider);
              },
              child: Text(l10n.commonRetry),
            ),
          ),
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
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardSnapshotProvider);
        await ref.read(dashboardSnapshotProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          hPad,
          AppSpacing.s12,
          hPad,
          kTabBarOffset + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _NetWorthHero(
            baseCurrency: baseCurrency,
            netWorth: netWorth,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
          ),
          if (totalAssets == Decimal.zero &&
              totalLiabilities == Decimal.zero) ...[
            const SizedBox(height: AppSpacing.s16),
            AppEmptyState(
              icon: FLucideIcons.landmark,
              title: AppLocalizations.of(context).wealthEmptyTitle,
              message: AppLocalizations.of(context).wealthEmptyBody,
              action: FButton(
                onPress: () => context.push(FinanceRoutes.wealthAccountNew),
                prefix: const Icon(FLucideIcons.plus),
                child: Text(AppLocalizations.of(context).wealthEmptyAction),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s16),
          const _WealthSectionGrid(),
          const SizedBox(height: AppSpacing.s16),
          const WealthPerspectiveSection(),
        ],
      ),
    );
  }
}

class _NetWorthHero extends ConsumerWidget {
  const _NetWorthHero({
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
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      borderRadius: AppRadius.xlg,
      borderless: true,
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeNetWorthTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
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
                  style: TypographyTokens.numericDisplay,
                  showSign: netWorth.toDouble() < 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          DefaultTextStyle.merge(
            style: context.captionStyle,
            child: Wrap(
              spacing: AppSpacing.s6,
              children: [
                Text(
                  '${l10n.dashboardNetWorthAssetsLabel} '
                  '${formatters.currency(totalAssets, code: baseCurrency)}',
                ),
                const Text('·'),
                Text(
                  '${l10n.dashboardNetWorthLiabilitiesLabel} '
                  '${formatters.currency(totalLiabilities, code: baseCurrency)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WealthSectionGrid extends StatelessWidget {
  const _WealthSectionGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <_WealthSectionSpec>[
      _WealthSectionSpec(
        icon: FLucideIcons.slidersHorizontal,
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
        icon: FLucideIcons.bellRing,
        title: l10n.wealthWatchlistSectionTitle,
        subtitle: l10n.wealthWatchlistSectionSubtitle,
        path: FinanceRoutes.wealthWatchlist,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.landmark,
        title: l10n.wealthLiabilitiesSectionTitle,
        subtitle: l10n.wealthLiabilitiesSectionSubtitle,
        path: FinanceRoutes.wealthLiabilities,
      ),
    ];
    return AppGroupedActionList(
      actions: [
        for (final spec in sections)
          AppGroupedAction(
            icon: spec.icon,
            title: spec.title,
            subtitle: spec.subtitle,
            onPress: () => context.push(spec.path),
          ),
      ],
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
