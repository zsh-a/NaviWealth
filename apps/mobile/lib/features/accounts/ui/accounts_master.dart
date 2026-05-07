import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'account_labels.dart';

class AccountsMaster extends ConsumerWidget {
  const AccountsMaster({
    super.key,
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

    return MasterDetailShortcuts(
      onSelectNext: allIds == null || allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: 1),
      onSelectPrevious: allIds == null || allIds.isEmpty
          ? null
          : () => _selectAdjacent(context, allIds, delta: -1),
      child: embedded ? body : _StandaloneAccountsScaffold(child: body),
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
      path: AppRoutes.activityAccounts,
      selected: allIds[nextIndex],
    );
  }
}

class AccountsDetailEmpty extends StatelessWidget {
  const AccountsDetailEmpty({super.key});

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

class _StandaloneAccountsScaffold extends StatelessWidget {
  const _StandaloneAccountsScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.accountsAppBarTitle),
        actions: [
          IconButton(
            tooltip: l10n.accountsJournalTooltip,
            icon: const Icon(Icons.history),
            onPressed: () => context.go(AppRoutes.accountJournal),
          ),
          IconButton(
            tooltip: l10n.accountsTransferTooltip,
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => context.go(AppRoutes.accountTransfer),
          ),
        ],
      ),
      body: child,
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

    return ScrollNotificationHandler(
      child: ListView.builder(
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
              LiquidGlassCard(
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
      ),
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
      replaceSelectedQuery(
        context,
        path: AppRoutes.activityAccounts,
        selected: account.id,
      );
    } else {
      context.go(AppRoutes.account(account.id));
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
