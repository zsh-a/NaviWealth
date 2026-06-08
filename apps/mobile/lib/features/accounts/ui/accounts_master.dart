import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/account_balances_provider.dart';
import '../domain/account_balances.dart';
import 'account_grouped_sections.dart';

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
    final balancesAsync = ref.watch(accountBalancesByIdProvider);
    final allIds = accountsAsync.value
        ?.where((a) => !a.archived)
        .map((a) => a.id)
        .toList();

    final body = accountsAsync.whenOrLoading(
      data: (accounts) {
        final visibleAccounts = accounts.where((a) => !a.archived).toList();
        return visibleAccounts.isEmpty
            ? const _EmptyAccounts()
            : _AccountsByType(
                accounts: visibleAccounts,
                balances: balancesAsync.value ?? const {},
                selectedId: selectedId,
                inMasterDetail: inMasterDetail,
              );
      },      error: (_, _) => Center(
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () {
              ref
                ..invalidate(accountsStreamProvider)
                ..invalidate(accountBalancesByIdProvider);
            },
            child: Text(l10n.commonRetry),
          ),
        ),
      ),
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
      path: AppRoutes.wealthAccounts,
      selected: allIds[nextIndex],
    );
  }
}

class AccountsDetailEmpty extends StatelessWidget {
  const AccountsDetailEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.navAccounts,
      showBack: false,
      childPad: false,
      child: MasterDetailEmpty(
        icon: FLucideIcons.landmark,
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
    return AppPageScaffold(
      title: l10n.navAccounts,
      actions: [
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountsCreateAction),
            child: const Icon(FLucideIcons.creditCard),
          ),
          semanticsLabel: l10n.accountsCreateAction,
          onPress: () => context.go(AppRoutes.wealthAccountNew),
        ),
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountsJournalAction),
            child: const Icon(FLucideIcons.history),
          ),
          semanticsLabel: l10n.accountsJournalAction,
          onPress: () => context.go(AppRoutes.journalEntries),
        ),
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountsTransferAction),
            child: const Icon(FLucideIcons.arrowLeftRight),
          ),
          semanticsLabel: l10n.accountsTransferAction,
          onPress: () => context.go(AppRoutes.transfer),
        ),
      ],
      childPad: false,
      child: child,
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.landmark,
      title: l10n.accountsEmptyHint,
      action: FButton(
        variant: FButtonVariant.primary,
        onPress: () => context.go(AppRoutes.wealthAccountNew),
        prefix: const Icon(FLucideIcons.creditCard),
        child: Text(l10n.accountFormCreateTitle),
      ),
    );
  }
}

class _AccountsByType extends StatelessWidget {
  const _AccountsByType({
    required this.accounts,
    required this.balances,
    required this.selectedId,
    required this.inMasterDetail,
  });

  final List<Account> accounts;
  final Map<String, AccountBalances> balances;
  final String? selectedId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        hPad,
        AppSpacing.s4,
        hPad,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        AccountsGroupedSections(
          accounts: accounts,
          balances: balances,
          selectedId: selectedId,
          heroEnabled: !inMasterDetail,
          onAccountPressed: _openAccount,
        ),
      ],
    );
  }

  void _openAccount(BuildContext context, Account account) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(
        context,
        path: AppRoutes.wealthAccounts,
        selected: account.id,
      );
    } else {
      context.go(AppRoutes.wealthAccount(account.id));
    }
  }
}
