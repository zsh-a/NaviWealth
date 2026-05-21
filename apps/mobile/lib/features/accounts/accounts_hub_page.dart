import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/format/providers.dart';
import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../home/data/dashboard_providers.dart';
import 'data/account_balances_provider.dart';
import 'domain/account_balances.dart';
import 'ui/account_grouped_sections.dart';
import 'ui/accounts_action_panel.dart';

/// Accounts Hub — account-centric view of every wealth container.
///
/// Section layout follows the new [AccountCategory] taxonomy: Cash /
/// Bank / Broker / Crypto / Credit / Loan / Asset / Liability. Each
/// row is one account container; rows with more than one non-zero unit
/// expand into per-currency / per-asset sub-rows ("IBKR · USD $12k ·
/// HKD $18k · AAPL 20").
///
/// Net-worth pulse stays at the top as a compact reference strip — the
/// account list is the page's main content.
class AccountsHubPage extends ConsumerWidget {
  const AccountsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final balancesAsync = ref.watch(accountBalancesByIdProvider);
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.navAccounts),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.add_outlined),
            semanticsLabel: l10n.accountsActionsTitle,
            onPress: () => showAccountsActionPanel(context),
          ),
        ],
      ),
      childPad: false,
      child: accountsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => Center(child: Text(l10n.commonLoadFailed)),
        data: (accounts) {
          // Filter: user-created wealth containers only. System
          // accounts (income / expense / equity sub-trees) are
          // ledger plumbing and don't belong on the hub surface.
          final containers = accounts
              .where((a) => !a.archived)
              .where(_isUserContainer)
              .toList();
          final balances = balancesAsync.value ?? const {};
          final snapshot = snapshotAsync.value;
          return _AccountsHubBody(
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
  // System accounts persist with side = income / expense / equity. The
  // user hub renders only asset / liability sides.
  return a.category == AccountSide.asset || a.category == AccountSide.liability;
}

class _AccountsHubBody extends StatelessWidget {
  const _AccountsHubBody({
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
    final hPad = Breakpoints.isMobile(width) ? 16.0 : 24.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        hPad,
        4,
        hPad,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _NetPulseStrip(
          baseCurrency: baseCurrency,
          netWorth: netWorth,
          totalAssets: totalAssets,
          totalLiabilities: totalLiabilities,
        ),
        const SizedBox(height: 14),
        _PortfolioHubLink(),
        const SizedBox(height: 10),
        _DcaSimulatorLink(),
        const SizedBox(height: 10),
        _WatchlistLink(),
        const SizedBox(height: 10),
        _IncomePlannerLink(),
        const SizedBox(height: 18),
        AccountsGroupedSections(
          accounts: accounts,
          balances: balances,
          allowExpansion: true,
          onAccountPressed: (context, account) =>
              context.push(AppRoutes.accountListItem(account.id)),
        ),
        const SizedBox(height: 8),
        _BankAccountsLink(),
      ],
    );
  }
}

class _NetPulseStrip extends ConsumerWidget {
  const _NetPulseStrip({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeNetWorthTitle.toUpperCase(),
            style: context.theme.typography.xs2.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedMoneyText(
            amount: netWorth.toDouble(),
            currencyCode: baseCurrency,
            style: TypographyTokens.numericTitle.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
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

class _BankAccountsLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(AppRoutes.accountsList),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.tune_outlined,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(
          l10n.accountsHubManageBankAccounts,
          style: context.theme.typography.sm.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        suffix: Icon(Icons.chevron_right, color: colors.mutedForeground),
      ),
    );
  }
}

class _PortfolioHubLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(AppRoutes.accountsPortfolioHub),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.stacked_line_chart,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(l10n.portfolioHubTitle),
        subtitle: Text(l10n.portfolioHubAccountsEntrySubtitle),
        suffix: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

class _WatchlistLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(AppRoutes.accountsWatchlist),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(l10n.watchlistTitle),
        subtitle: Text(l10n.watchlistAccountsEntrySubtitle),
        suffix: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

class _IncomePlannerLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(AppRoutes.accountsIncomePlanner),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.candlestick_chart_outlined,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(l10n.incomePlannerTitle),
        subtitle: Text(l10n.incomePlannerAccountsEntrySubtitle),
        suffix: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

class _DcaSimulatorLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return FCard.raw(
      child: FTile(
        onPress: () => context.push(AppRoutes.accountsDcaSimulator),
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.event_repeat_outlined,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(l10n.dcaSimulatorTitle),
        subtitle: Text(l10n.dcaSimulatorAccountsEntrySubtitle),
        suffix: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
