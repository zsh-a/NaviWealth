import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/global_action_panel.dart';
import '../../app/route_paths.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../home/data/dashboard_providers.dart';
import '../home/domain/dashboard_models.dart';

/// Accounts Hub — the 5th primary tab.
///
/// One scrollable surface that aggregates everything the user owns or owes,
/// grouped into four sections (Cash & Deposits, Investments, Physical,
/// Liabilities). Each row is a `CategoryItem` whose `routeHint` deep-links
/// into the corresponding detail page (asset detail / physical detail /
/// liability detail), preserving the existing detail flows untouched.
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
          data: (snapshot) =>
              _AccountsHubBody(snapshot: snapshot, baseCurrency: snapshot.baseCurrency),
        ),
      ),
    );
  }
}

class _AccountsHubBody extends StatelessWidget {
  const _AccountsHubBody({required this.snapshot, required this.baseCurrency});

  final DashboardSnapshot snapshot;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = Breakpoints.isMobile(width)
        ? const EdgeInsets.fromLTRB(16, 8, 16, 80)
        : const EdgeInsets.fromLTRB(24, 12, 24, 96);

    final groups = _groupAllocations(snapshot.allocations);
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: padding,
      children: [
        _NetSummaryHeader(snapshot: snapshot),
        const SizedBox(height: 16),
        if (groups.cashAndDeposits.isNotEmpty) ...[
          _AccountsSection(
            title: l10n.accountsHubSectionCashDeposits,
            items: groups.cashAndDeposits,
            baseCurrency: baseCurrency,
          ),
          const SizedBox(height: 16),
        ],
        if (groups.investments.isNotEmpty) ...[
          _AccountsSection(
            title: l10n.accountsHubSectionInvestments,
            items: groups.investments,
            baseCurrency: baseCurrency,
          ),
          const SizedBox(height: 16),
        ],
        if (groups.physical.isNotEmpty) ...[
          _AccountsSection(
            title: l10n.accountsHubSectionPhysical,
            items: groups.physical,
            baseCurrency: baseCurrency,
          ),
          const SizedBox(height: 16),
        ],
        if (groups.liabilities.isNotEmpty) ...[
          _AccountsSection(
            title: l10n.accountsHubSectionLiabilities,
            items: groups.liabilities,
            baseCurrency: baseCurrency,
            isLiability: true,
          ),
          const SizedBox(height: 16),
        ],
        _BankAccountsLink(),
      ],
    );
  }
}

class _NetSummaryHeader extends StatelessWidget {
  const _NetSummaryHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = snapshot.netWorth.amount.toDouble();
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeNetWorthTitle,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedMoneyText(
              amount: total,
              currencyCode: snapshot.baseCurrency,
              style: TypographyTokens.numericDisplay,
              showSign: total < 0,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: l10n.dashboardNetWorthAssetsLabel,
                    amount: snapshot.totalAssets.amount.toDouble(),
                    currency: snapshot.baseCurrency,
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: context.theme.colors.border,
                ),
                Expanded(
                  child: _StatCell(
                    label: l10n.dashboardNetWorthLiabilitiesLabel,
                    amount: snapshot.totalLiabilities.amount.toDouble(),
                    currency: snapshot.baseCurrency,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          MoneyText(
            amount: amount,
            currencyCode: currency,
            style: TypographyTokens.numericTitle,
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
    this.isLiability = false,
  });

  final String title;
  final List<CategoryItem> items;
  final String baseCurrency;
  final bool isLiability;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<Decimal>(
      Decimal.zero,
      (acc, it) => acc + it.valueInBase.amount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MoneyText(
                amount: total.toDouble(),
                currencyCode: baseCurrency,
                style: context.theme.typography.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        FCard.raw(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _AccountRow(
                  item: items[i],
                  baseCurrency: baseCurrency,
                  isLiability: isLiability,
                ),
                if (i < items.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: FDivider(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.item,
    required this.baseCurrency,
    required this.isLiability,
  });

  final CategoryItem item;
  final String baseCurrency;
  final bool isLiability;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final amount = item.valueInBase.amount.toDouble();
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
                color: colors.muted,
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
            MoneyText(
              amount: isLiability ? -amount : amount,
              currencyCode: baseCurrency,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(CategoryItem item) {
    if (isLiability) return Icons.south_east_outlined;
    // Best-effort mapping; could swap to AssetCategoryVisuals.icon if we
    // threaded the parent category through. CategoryItem doesn't carry
    // category itself, so we fall back to a neutral wallet glyph.
    return Icons.account_balance_wallet_outlined;
  }
}

class _BankAccountsLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: FTappable(
        onPress: () => context.push(AppRoutes.accountsList),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.theme.colors.muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.account_balance_outlined,
                  size: 18,
                  color: context.theme.colors.mutedForeground,
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
                color: context.theme.colors.mutedForeground,
              ),
            ],
          ),
        ),
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
  // Sort each section by base-currency value descending for "biggest first".
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

