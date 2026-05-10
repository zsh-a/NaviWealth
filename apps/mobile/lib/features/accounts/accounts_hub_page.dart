import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/global_action_panel.dart';
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
import 'ui/account_labels.dart';

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
            onPress: () => showGlobalActionPanel(context),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: accountsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text('$e')),
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
              totalAssets:
                  snapshot?.totalAssets.amount ?? Decimal.zero,
              totalLiabilities:
                  snapshot?.totalLiabilities.amount ?? Decimal.zero,
            );
          },
        ),
      ),
    );
  }
}

bool _isUserContainer(Account a) {
  // System accounts persist with side = income / expense / equity. The
  // user hub renders only asset / liability sides.
  return a.category == AccountSide.asset ||
      a.category == AccountSide.liability;
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
    final l10n = AppLocalizations.of(context);

    final groups = _groupByCategory(accounts);

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
        const SizedBox(height: 18),
        for (final entry in groups.entries)
          _AccountsSection(
            title: accountCategoryLabel(l10n, entry.key),
            accounts: entry.value,
            balances: balances,
            baseCurrency: baseCurrency,
          ),
        const SizedBox(height: 8),
        _BankAccountsLink(),
      ],
    );
  }
}

Map<AccountCategory, List<Account>> _groupByCategory(
  List<Account> accounts,
) {
  // Render order — Cash first, then Bank, Broker, Crypto, Credit, Loan,
  // Asset (other), Liability (other). Empty groups are dropped.
  const order = [
    AccountCategory.cash,
    AccountCategory.bank,
    AccountCategory.broker,
    AccountCategory.crypto,
    AccountCategory.credit,
    AccountCategory.loan,
    AccountCategory.asset,
    AccountCategory.liability,
  ];
  final out = <AccountCategory, List<Account>>{};
  for (final cat in order) {
    final group = accounts.where((a) => a.type == cat).toList();
    if (group.isEmpty) continue;
    out[cat] = group;
  }
  return out;
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
              letterSpacing: 0.6,
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

class _AccountsSection extends StatelessWidget {
  const _AccountsSection({
    required this.title,
    required this.accounts,
    required this.balances,
    required this.baseCurrency,
  });

  final String title;
  final List<Account> accounts;
  final Map<String, AccountBalances> balances;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              title.toUpperCase(),
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SoftCard(
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  _AccountRow(
                    account: accounts[i],
                    balances: balances[accounts[i].id] ??
                        AccountBalances.empty(accounts[i].id),
                    baseCurrency: baseCurrency,
                  ),
                  if (i < accounts.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        height: 1,
                        color: colors.foreground.withValues(alpha: 0.05),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Account row — collapsed by default, tap to expand into per-unit
/// child rows when the container holds more than one unit.
class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.account,
    required this.balances,
    required this.baseCurrency,
  });

  final Account account;
  final AccountBalances balances;
  final String baseCurrency;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final account = widget.account;
    final balances = widget.balances;
    final isMulti = balances.isMultiUnit;
    final primaryLeg = balances.legFor(account.currency) ??
        (balances.legs.isNotEmpty ? balances.legs.first : null);

    return Column(
      children: [
        FTappable(
          onPress: () {
            if (isMulti) {
              setState(() => _expanded = !_expanded);
            } else {
              context.push(AppRoutes.accountListItem(account.id));
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.foreground.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _iconFor(account.type),
                    size: 18,
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account.name,
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (account.institution != null &&
                          account.institution!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            account.institution!,
                            style: context.theme.typography.xs.copyWith(
                              color: colors.mutedForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (primaryLeg != null)
                      _PrimaryAmount(leg: primaryLeg)
                    else
                      Text(
                        '—',
                        style: context.theme.typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    if (isMulti)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _multiHint(balances),
                          style: context.theme.typography.xs2.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
                if (isMulti)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: colors.mutedForeground.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isMulti && _expanded)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 64,
              end: 14,
              bottom: 10,
            ),
            child: Column(
              children: [
                for (final leg in balances.legs)
                  if (leg.unit != account.currency || balances.legs.length > 1)
                    _SubLegRow(leg: leg),
              ],
            ),
          ),
      ],
    );
  }

  String _multiHint(AccountBalances balances) {
    final units = balances.legs.map((l) => l.unit).toList();
    if (units.length <= 3) return units.join(' · ');
    return '${units.take(2).join(' · ')} · +${units.length - 2}';
  }

  IconData _iconFor(AccountCategory cat) {
    return switch (cat) {
      AccountCategory.cash => Icons.payments_outlined,
      AccountCategory.bank => Icons.account_balance_outlined,
      AccountCategory.broker => Icons.show_chart_outlined,
      AccountCategory.crypto => Icons.currency_bitcoin,
      AccountCategory.credit => Icons.credit_card_outlined,
      AccountCategory.loan => Icons.request_quote_outlined,
      AccountCategory.asset => Icons.inventory_2_outlined,
      AccountCategory.liability => Icons.south_east_outlined,
    };
  }
}

class _PrimaryAmount extends ConsumerWidget {
  const _PrimaryAmount({required this.leg});

  final AccountBalanceLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatters = context.formatters(ref);
    final amount = leg.units;
    final text = leg.isFiatLike
        ? formatters.currency(amount, code: leg.unit)
        : '${_trimDecimal(amount)} ${_assetSymbol(leg.unit)}';
    return Text(
      text,
      style: context.theme.typography.sm.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _SubLegRow extends ConsumerWidget {
  const _SubLegRow({required this.leg});

  final AccountBalanceLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final formatters = context.formatters(ref);
    final amount = leg.units;
    final text = leg.isFiatLike
        ? formatters.currency(amount, code: leg.unit)
        : '${_trimDecimal(amount)} ${_assetSymbol(leg.unit)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              leg.isFiatLike ? leg.unit : _assetSymbol(leg.unit),
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            text,
            style: context.theme.typography.sm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _assetSymbol(String unit) {
  // unit format is `<market>:<symbol>` for asset legs; show just the
  // symbol when present so the row reads "AAPL", not "us_stock:AAPL".
  final colon = unit.indexOf(':');
  return colon < 0 ? unit : unit.substring(colon + 1);
}

String _trimDecimal(Decimal d) {
  if (d == Decimal.zero) return '0';
  final s = d.toString();
  if (!s.contains('.')) return s;
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _BankAccountsLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      onPress: () => context.push(AppRoutes.accountsList),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.accountsHubManageBankAccounts,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: colors.mutedForeground,
          ),
        ],
      ),
    );
  }
}
