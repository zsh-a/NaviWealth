import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/master_detail_layout.dart';
import '../../app/selection_query.dart';
import '../../core/shortcuts/master_detail_shortcuts.dart';
import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'account_form_page.dart';

/// Lists every active account, grouped by [AccountType].
///
/// Tapping an account opens its edit form; the floating action button
/// creates a new one. Soft-deleted / archived accounts hide here — the
/// archived-accounts surface is intentionally separate so the primary list
/// stays focused on the user's day-to-day book of accounts.
///
/// At desktop width (≥ 1240) the page renders as a master-detail surface
/// (FIR-106): the list lives on the left, and the account edit form for
/// the `?selected=<id>` row lives on the right.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key, this.embedded = false});

  /// When true, skips the Scaffold so the page can be embedded
  /// inside another Scaffold (e.g., the Activity tab).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final selected = selectedQueryOf(context);
        if (masterDetail) {
          return Scaffold(
            body: MasterDetailLayout(
              master: _AccountsMaster(
                selectedId: selected,
                inMasterDetail: true,
              ),
              detail: selected == null
                  ? const _AccountsDetailEmpty()
                  : AccountFormPage(accountId: selected),
            ),
          );
        }
        return _AccountsMaster(
          selectedId: null,
          inMasterDetail: false,
          embedded: embedded,
        );
      },
    );
  }
}

class _AccountsMaster extends ConsumerWidget {
  const _AccountsMaster({
    required this.selectedId,
    required this.inMasterDetail,
    this.embedded = false,
  });

  final String? selectedId;
  final bool inMasterDetail;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);

    // Flat ordered list of account IDs for j/k navigation.
    final allIds = accountsAsync.value?.map((a) => a.id).toList();

    final body = accountsAsync.when(
      data: (accounts) => accounts.isEmpty
          ? const _EmptyAccounts()
          : _AccountsByType(
              accounts: accounts,
              selectedId: selectedId,
              inMasterDetail: inMasterDetail,
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l10n.accountsLoadError('$e'))),
    );

    if (embedded) {
      return MasterDetailShortcuts(
        onSelectNext: allIds == null || allIds.isEmpty
            ? null
            : () => _selectAdjacent(context, allIds, delta: 1),
        onSelectPrevious: allIds == null || allIds.isEmpty
            ? null
            : () => _selectAdjacent(context, allIds, delta: -1),
        child: body,
      );
    }

    return MasterDetailShortcuts(
      onSelectNext: allIds == null || allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: 1),
      onSelectPrevious: allIds == null || allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: -1),
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(l10n.accountsAppBarTitle),
          actions: [
            IconButton(
              tooltip: 'Journal',
              icon: const Icon(Icons.history),
              onPressed: () => context.go('/activity/accounts/journal'),
            ),
            IconButton(
              tooltip: 'New transfer',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => context.go('/activity/accounts/transfer'),
            ),
          ],
        ),
        body: body,
        floatingActionButton: ScrollAwareFab(
          child: AppFab.extended(
            onPressed: () => context.go('/activity/accounts/new'),
            icon: const Icon(Icons.add),
            label: Text(l10n.accountsCreateAction),
          ),
        ),
      ),
    );
  }

  void _selectAdjacent(
    BuildContext context,
    List<String> allIds, {
    required int delta,
  }) {
    if (allIds.isEmpty) return;
    final current = selectedId;
    int nextIndex;
    if (current == null) {
      nextIndex = delta > 0 ? 0 : allIds.length - 1;
    } else {
      final idx = allIds.indexOf(current);
      if (idx < 0) {
        nextIndex = 0;
      } else {
        nextIndex = (idx + delta) % allIds.length;
        if (nextIndex < 0) nextIndex += allIds.length;
      }
    }
    replaceSelectedQuery(
      context,
      path: '/activity/accounts',
      selected: allIds[nextIndex],
    );
  }
}

class _AccountsDetailEmpty extends StatelessWidget {
  const _AccountsDetailEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.accountsAppBarTitle)),
      body: MasterDetailEmpty(
        icon: Icons.account_balance_outlined,
        message: l10n.accountsDetailEmpty,
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined, size: 48),
            const SizedBox(height: Spacing.s12),
            Text(l10n.accountsEmptyHint, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AccountsByType extends StatelessWidget {
  const _AccountsByType({
    required this.accounts,
    required this.selectedId,
    required this.inMasterDetail,
  });

  final List<Account> accounts;
  final String? selectedId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grouped = <AccountType, List<Account>>{};
    for (final a in accounts) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    final order = AccountType.values
        .where((t) => grouped.containsKey(t))
        .toList(growable: false);

    return ListView.builder(
      padding: Spacing.pageMobile,
      itemCount: order.length,
      itemBuilder: (context, i) {
        final type = order[i];
        final group = grouped[type]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: Spacing.s8,
                bottom: Spacing.s8,
              ),
              child: Text(
                accountTypeLabel(l10n, type),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final a in group)
                    _AccountTile(
                      account: a,
                      selected: a.id == selectedId,
                      heroEnabled: !inMasterDetail,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.s12),
          ],
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.selected,
    required this.heroEnabled,
  });

  final Account account;
  final bool selected;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : null,
      child: ListTile(
        title: OptionalHero(
          tag: 'account-${account.id}-name',
          enabled: heroEnabled,
          child: Text(account.name),
        ),
        subtitle: Text(_subtitleFor(account)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _onTap(context),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(context, path: '/activity/accounts', selected: account.id);
    } else {
      context.go('/activity/accounts/${account.id}');
    }
  }

  String _subtitleFor(Account a) {
    final parts = <String>[a.currency];
    if (a.institution != null && a.institution!.isNotEmpty) {
      parts.add(a.institution!);
    }
    return parts.join(' · ');
  }
}

/// Localised display label for an [AccountType]. Resolved through the ARB
/// tables so list, detail, and form screens stay in sync without each one
/// carrying its own switch.
String accountTypeLabel(AppLocalizations l10n, AccountType t) {
  return switch (t) {
    AccountType.brokerage => l10n.accountTypeBrokerage,
    AccountType.bank => l10n.accountTypeBank,
    AccountType.cryptoWallet => l10n.accountTypeCryptoWallet,
    AccountType.realEstate => l10n.accountTypeRealEstate,
    AccountType.vehicle => l10n.accountTypeVehicle,
    AccountType.liability => l10n.accountTypeLiability,
    AccountType.cash => l10n.accountTypeCash,
    AccountType.other => l10n.accountTypeOther,
  };
}

/// FIR-126 — localised display label for an [AccountCategory]. Used by
/// the account form's category dropdown and by anywhere else that needs
/// to print the accounting classification.
String accountCategoryLabel(AppLocalizations l10n, AccountCategory c) {
  return switch (c) {
    AccountCategory.asset => l10n.accountCategoryAsset,
    AccountCategory.liability => l10n.accountCategoryLiability,
    AccountCategory.income => l10n.accountCategoryIncome,
    AccountCategory.expense => l10n.accountCategoryExpense,
    AccountCategory.equity => l10n.accountCategoryEquity,
  };
}
