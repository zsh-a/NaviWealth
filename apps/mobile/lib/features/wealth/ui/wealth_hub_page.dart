import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
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
/// surface: Accounts, Holdings (portfolio), Watchlist, Liabilities, Income
/// Projection. Phase C replaced the bare ListView that lived under
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

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.wealthHubTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.plus),
            semanticsLabel: l10n.accountsActionsTitle,
            onPress: () => showWealthActionPanel(context),
          ),
        ],
      ),
      childPad: false,
      child: accountsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => Center(child: Text(l10n.commonLoadFailed)),
        data: (accounts) {
          final containers = accounts
              .where((a) => !a.archived)
              .where(_isUserContainer)
              .toList();
          final balances = balancesAsync.value ?? const {};
          final snapshot = snapshotAsync.value;
          return _WealthHubBody(
            accounts: containers,
            balances: balances,
            baseCurrency: snapshot?.baseCurrency ?? 'USD',
            netWorth: snapshot?.netWorth.amount ?? Decimal.zero,
            totalAssets: snapshot?.totalAssets.amount ?? Decimal.zero,
            totalLiabilities: snapshot?.totalLiabilities.amount ?? Decimal.zero,
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
        AppSpacing.s24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _NetWorthHero(
          baseCurrency: baseCurrency,
          netWorth: netWorth,
          totalAssets: totalAssets,
          totalLiabilities: totalLiabilities,
        ),
        const SizedBox(height: AppSpacing.s20),
        const _WealthSectionGrid(),
        const SizedBox(height: AppSpacing.s20),
        const WealthPerspectiveSection(),
        const SizedBox(height: AppSpacing.s20),
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
      borderRadius: 18,
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
              spacing: 6,
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
      _WealthSectionSpec(
        icon: FLucideIcons.banknote,
        title: l10n.wealthIncomeProjectionTitle,
        subtitle: l10n.wealthIncomeProjectionSubtitle,
        path: AppRoutes.wealthIncomeProjection,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 620;
        if (!twoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final spec in sections) ...[
                _WealthSectionCard(spec: spec),
                const SizedBox(height: AppSpacing.s12),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < sections.length; i += 2) {
          final left = sections[i];
          final right = i + 1 < sections.length ? sections[i + 1] : null;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _WealthSectionCard(spec: left)),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: right == null
                        ? const SizedBox()
                        : _WealthSectionCard(spec: right),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
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

class _WealthSectionCard extends StatelessWidget {
  const _WealthSectionCard({required this.spec});

  final _WealthSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(spec.path),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(spec.icon, size: 18, color: colors.mutedForeground),
        ),
        title: Text(spec.title),
        subtitle: Text(spec.subtitle),
        suffix: const Icon(FLucideIcons.chevronRight, size: 18),
      ),
    );
  }
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
    return FScaffold(
      header: FHeader.nested(title: Text(l10n.wealthIncomeProjectionTitle)),
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
