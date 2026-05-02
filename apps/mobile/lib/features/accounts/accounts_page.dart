import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Lists every active account, grouped by [AccountType].
///
/// Tapping an account opens its edit form; the floating action button
/// creates a new one. Soft-deleted / archived accounts hide here — the
/// archived-accounts surface is intentionally separate so the primary list
/// stays focused on the user's day-to-day book of accounts.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.accountsAppBarTitle)),
      body: accountsAsync.when(
        data: (accounts) => accounts.isEmpty
            ? const _EmptyAccounts()
            : _AccountsByType(accounts: accounts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.accountsLoadError('$e'))),
      ),
      floatingActionButton: AppFab.extended(
        onPressed: () => context.go('/accounts/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.accountsCreateAction),
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
  const _AccountsByType({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final a in group)
                    ListTile(
                      title: Text(a.name),
                      subtitle: Text(_subtitleFor(a)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/accounts/${a.id}'),
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
