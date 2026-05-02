import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/account.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';

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
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: accountsAsync.when(
        data: (accounts) => accounts.isEmpty
            ? const _EmptyAccounts()
            : _AccountsByType(accounts: accounts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: AppFab.extended(
        onPressed: () => context.go('/accounts/new'),
        icon: const Icon(Icons.add),
        label: const Text('新建账户'),
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_outlined, size: 48),
            SizedBox(height: Spacing.s12),
            Text('还没有账户。点击右下角新建一个，再去录入资产。', textAlign: TextAlign.center),
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
                accountTypeLabel(type),
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

/// Localisable label for an [AccountType]. Kept here rather than in the
/// l10n bundle for now — these labels are also used inside the entry
/// forms and we don't want to fork the strings while the UX still moves.
String accountTypeLabel(AccountType t) {
  return switch (t) {
    AccountType.brokerage => '券商账户',
    AccountType.bank => '银行账户',
    AccountType.cryptoWallet => '加密钱包',
    AccountType.realEstate => '不动产账户',
    AccountType.vehicle => '车辆账户',
    AccountType.liability => '负债账户',
    AccountType.cash => '现金账户',
    AccountType.other => '其他账户',
  };
}
