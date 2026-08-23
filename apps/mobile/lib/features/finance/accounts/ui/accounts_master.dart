import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shell/selection_query.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/account_balances_provider.dart';
import '../domain/account_balances.dart';
import '../domain/account_semantics.dart';
import 'account_grouped_sections.dart';

class AccountsMaster extends ConsumerWidget {
  const AccountsMaster({
    super.key,
    required this.selectedId,
    required this.inMasterDetail,
  });

  final String? selectedId;
  final bool inMasterDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final balancesAsync = ref.watch(accountBalancesByIdProvider);
    final allIds = accountsAsync.value
        ?.where((a) => !a.archived && isCustodyAccountCategory(a.type))
        .map((a) => a.id)
        .toList();

    final body = accountsAsync.whenOrLoading(
      context: context,
      data: (accounts) {
        final visibleAccounts = accounts
            .where((a) => !a.archived && isCustodyAccountCategory(a.type))
            .toList();
        return visibleAccounts.isEmpty
            ? const _EmptyAccounts()
            : _AccountsByType(
                accounts: visibleAccounts,
                balances: balancesAsync.value ?? const {},
                selectedId: selectedId,
                inMasterDetail: inMasterDetail,
              );
      },
      error: (_, _) => Center(
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          retryLabel: l10n.commonRetry,
          onRetry: () {
            ref
              ..invalidate(accountsStreamProvider)
              ..invalidate(accountBalancesByIdProvider);
          },
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
      child: _StandaloneAccountsScaffold(child: body),
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
      path: FinanceRoutes.wealthAccounts,
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
        AppHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.accountsCreateAction,
          onPress: () => context.push(FinanceRoutes.wealthAccountNew),
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
        onPress: () => context.push(FinanceRoutes.wealthAccountNew),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = Breakpoints.isMobile(constraints.maxWidth)
            ? AppSpacing.s16
            : AppSpacing.s24;
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
              containerTransformEnabled: !inMasterDetail,
              onAccountPressed: _openAccount,
            ),
          ],
        );
      },
    );
  }

  void _openAccount(BuildContext context, Account account) {
    // Push-mode rows navigate through their own AppContainerTransform, so
    // this callback effectively only fires from the master-detail surface;
    // the `push` branch stays as a safety net for non-transform callers.
    if (inMasterDetail) {
      replaceSelectedQuery(
        context,
        path: FinanceRoutes.wealthAccounts,
        selected: account.id,
      );
    } else {
      context.push(FinanceRoutes.wealthAccount(account.id));
    }
  }
}
