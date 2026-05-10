import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/global_action_panel.dart';
import '../../app/route_paths.dart';
import '../../core/format/formatters.dart';
import '../../core/format/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../home/data/dashboard_providers.dart';
import '../home/domain/dashboard_models.dart';

/// Accounts Hub — the 5th primary tab.
///
/// Account-first layout: a slim "net worth pulse" strip up top so the
/// reference number is always visible, then the user's actual accounts
/// take over the surface — Cash & Deposits / Investments / Physical /
/// Liabilities sections each list every entity with both native amount
/// and base-currency value (the "structure" the user thinks in).
///
/// We intentionally weaken the net-worth hero compared to Home — Home
/// answers "where do I stand?", Accounts answers "what do I own?".
class AccountsHubPage extends ConsumerWidget {
  const AccountsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
        child: snapshotAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text('$e')),
          data: (snapshot) => _AccountsHubBody(snapshot: snapshot),
        ),
      ),
    );
  }
}

class _AccountsHubBody extends ConsumerWidget {
  const _AccountsHubBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? 16.0 : 24.0;
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final groups = _groupAllocations(snapshot.allocations);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        hPad,
        4,
        hPad,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _NetPulseStrip(snapshot: snapshot, formatters: formatters),
        const SizedBox(height: 18),
        if (groups.cashAndDeposits.isNotEmpty)
          _AccountsSection(
            title: l10n.accountsHubSectionCashDeposits,
            items: groups.cashAndDeposits,
            baseCurrency: snapshot.baseCurrency,
            formatters: formatters,
          ),
        if (groups.investments.isNotEmpty)
          _AccountsSection(
            title: l10n.accountsHubSectionInvestments,
            items: groups.investments,
            baseCurrency: snapshot.baseCurrency,
            formatters: formatters,
          ),
        if (groups.physical.isNotEmpty)
          _AccountsSection(
            title: l10n.accountsHubSectionPhysical,
            items: groups.physical,
            baseCurrency: snapshot.baseCurrency,
            formatters: formatters,
          ),
        if (groups.liabilities.isNotEmpty)
          _AccountsSection(
            title: l10n.accountsHubSectionLiabilities,
            items: groups.liabilities,
            baseCurrency: snapshot.baseCurrency,
            formatters: formatters,
            isLiability: true,
          ),
        const SizedBox(height: 8),
        _BankAccountsLink(),
      ],
    );
  }
}

/// Slim "net pulse" strip — replaces the heavy net-worth hero card.
///
/// Renders as one inline row: net worth value · assets · liabilities.
/// Reads as a tiny status bar so the eye drops straight to the account
/// list below.
class _NetPulseStrip extends StatelessWidget {
  const _NetPulseStrip({required this.snapshot, required this.formatters});

  final DashboardSnapshot snapshot;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
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
            amount: snapshot.netWorth.amount.toDouble(),
            currencyCode: snapshot.baseCurrency,
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
                  '${formatters.currency(snapshot.totalAssets.amount, code: snapshot.baseCurrency)}',
                ),
                const Text('·'),
                Text(
                  '${l10n.dashboardNetWorthLiabilitiesLabel} '
                  '${formatters.currency(snapshot.totalLiabilities.amount, code: snapshot.baseCurrency)}',
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
    required this.items,
    required this.baseCurrency,
    required this.formatters,
    this.isLiability = false,
  });

  final String title;
  final List<CategoryItem> items;
  final String baseCurrency;
  final AppFormatters formatters;
  final bool isLiability;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<Decimal>(
      Decimal.zero,
      (acc, it) => acc + it.valueInBase.amount,
    );
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: context.theme.typography.xs2.copyWith(
                      color: colors.mutedForeground,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  formatters.currency(total, code: baseCurrency),
                  style: context.theme.typography.xs.copyWith(
                    color: colors.mutedForeground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SoftCard(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _AccountRow(
                    item: items[i],
                    baseCurrency: baseCurrency,
                    isLiability: isLiability,
                    formatters: formatters,
                  ),
                  if (i < items.length - 1)
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.item,
    required this.baseCurrency,
    required this.isLiability,
    required this.formatters,
  });

  final CategoryItem item;
  final String baseCurrency;
  final bool isLiability;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final nativeAmount = isLiability ? -item.nativeAmount : item.nativeAmount;
    final baseAmount = isLiability
        ? -item.valueInBase.amount
        : item.valueInBase.amount;
    final showFx = item.nativeCurrency != baseCurrency;
    return FTappable(
      onPress: item.routeHint == null
          ? null
          : () => context.push(item.routeHint!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                _iconFor(item),
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
                    item.name,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle != null && item.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.subtitle!,
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
                // Lead with native amount — that's how the user thinks
                // about each account ("how much CNY in招行", "how many
                // BTC"). Show base only as a small subline when there's
                // an FX gap.
                Text(
                  formatters.currency(nativeAmount, code: item.nativeCurrency),
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (showFx)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      formatters.currency(baseAmount, code: baseCurrency),
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(CategoryItem item) {
    if (isLiability) return Icons.south_east_outlined;
    final cur = item.nativeCurrency.toUpperCase();
    if (cur == 'BTC' || cur == 'ETH' || cur == 'USDT' || cur == 'USDC') {
      return Icons.currency_bitcoin;
    }
    return Icons.account_balance_outlined;
  }
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

class _AccountsHubGroups {
  const _AccountsHubGroups({
    required this.cashAndDeposits,
    required this.investments,
    required this.physical,
    required this.liabilities,
  });

  final List<CategoryItem> cashAndDeposits;
  final List<CategoryItem> investments;
  final List<CategoryItem> physical;
  final List<CategoryItem> liabilities;
}

_AccountsHubGroups _groupAllocations(List<CategoryAllocation> allocations) {
  final cash = <CategoryItem>[];
  final inv = <CategoryItem>[];
  final phys = <CategoryItem>[];
  final liab = <CategoryItem>[];
  for (final a in allocations) {
    switch (a.category) {
      case AssetCategory.cash:
      case AssetCategory.bondsAndFunds:
        cash.addAll(a.items);
      case AssetCategory.stock:
      case AssetCategory.etf:
      case AssetCategory.crypto:
        inv.addAll(a.items);
      case AssetCategory.realEstate:
      case AssetCategory.vehicle:
        phys.addAll(a.items);
      case AssetCategory.liability:
        liab.addAll(a.items);
    }
  }
  int cmp(CategoryItem a, CategoryItem b) =>
      b.valueInBase.amount.compareTo(a.valueInBase.amount);
  cash.sort(cmp);
  inv.sort(cmp);
  phys.sort(cmp);
  liab.sort(cmp);
  return _AccountsHubGroups(
    cashAndDeposits: cash,
    investments: inv,
    physical: phys,
    liabilities: liab,
  );
}
