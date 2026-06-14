import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../app/route_paths.dart';
import '../../../app/shell_chrome.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_balances_provider.dart';
import '../../accounts/domain/account_balances.dart';
import '../../accounts/ui/account_grouped_sections.dart';
import '../../home/data/dashboard_providers.dart';
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
    final accountsAsync = ref.watch(accountsStreamProvider);
    final balancesAsync = ref.watch(accountBalancesByIdProvider);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);

    return ShellTabScaffold(
      title: l10n.wealthHubTitle,
      childPad: false,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.accountsActionsTitle,
          onPress: () => showWealthActionPanel(context),
        ),
      ],
      child: accountsAsync.when(
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
                ref
                  ..invalidate(accountsStreamProvider)
                  ..invalidate(accountBalancesByIdProvider)
                  ..invalidate(dashboardSnapshotProvider);
              },
              child: Text(l10n.commonRetry),
            ),
          ),
        ),
        data: (accounts) {
          final containers = accounts
              .where((a) => !a.archived)
              .where(_isUserContainer)
              .toList();
          final balances = balancesAsync.value ?? const {};
          final snapshot = snapshotAsync.value;
          return PageSkeletonShell<Object>(
            isLoading: false,
            skeleton: const WealthHubSkeleton(),
            child: _WealthHubBody(
              accounts: containers,
              balances: balances,
              baseCurrency: snapshot?.baseCurrency ?? 'USD',
              netWorth: snapshot?.netWorth.amount ?? Decimal.zero,
              totalAssets: snapshot?.totalAssets.amount ?? Decimal.zero,
              totalLiabilities:
                  snapshot?.totalLiabilities.amount ?? Decimal.zero,
            ),
          );
        },
      ),
    );
  }
}

bool _isUserContainer(Account a) {
  return a.category == AccountSide.asset || a.category == AccountSide.liability;
}

class _WealthHubBody extends StatelessWidget {
  const _WealthHubBody({
    required this.accounts,
    required this.balances,
    required this.baseCurrency,
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
  });

  final List<Account> accounts;
  final Map<String, AccountBalances> balances;
  final String baseCurrency;
  final Decimal netWorth;
  final Decimal totalAssets;
  final Decimal totalLiabilities;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    return ListView(
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
        const SizedBox(height: AppSpacing.s16),
        const _WealthSectionGrid(),
        const SizedBox(height: AppSpacing.s16),
        const WealthPerspectiveSection(),
        const SizedBox(height: AppSpacing.s16),
        AccountsGroupedSections(
          accounts: accounts,
          balances: balances,
          allowExpansion: true,
          onAccountPressed: (context, account) =>
              context.push(AppRoutes.wealthAccount(account.id)),
        ),
      ],
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
    final colors = context.theme.colors;
    final formatters = context.formatters(ref);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s20),
      borderRadius: AppRadius.xlg,
      borderless: true,
      tinted: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeNetWorthTitle,
            style: context.theme.typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
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
          const SizedBox(height: AppSpacing.s8),
          DefaultTextStyle.merge(
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
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
        path: AppRoutes.wealthAccounts,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.chartLine,
        title: l10n.wealthHoldingsSectionTitle,
        subtitle: l10n.wealthHoldingsSectionSubtitle,
        path: AppRoutes.wealthPortfolio,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.bellRing,
        title: l10n.wealthWatchlistSectionTitle,
        subtitle: l10n.wealthWatchlistSectionSubtitle,
        path: AppRoutes.wealthWatchlist,
      ),
      _WealthSectionSpec(
        icon: FLucideIcons.landmark,
        title: l10n.wealthLiabilitiesSectionTitle,
        subtitle: l10n.wealthLiabilitiesSectionSubtitle,
        path: AppRoutes.wealthLiabilities,
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

/// Placeholder page for /wealth/income-projection. The full yield-by-holding
/// engine is a Phase C+ work item; for now this surfaces a "coming soon"
/// empty state so the route resolves and the section card has somewhere
/// to land.
class WealthIncomeProjectionPlaceholderPage extends StatelessWidget {
  const WealthIncomeProjectionPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.wealthIncomeProjectionTitle,
      childPad: false,
      child: Center(
        child: AppEmptyState(
          icon: FLucideIcons.banknote,
          title: l10n.wealthIncomeProjectionComingSoon,
        ),
      ),
    );
  }
}
