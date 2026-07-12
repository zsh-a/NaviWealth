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
        ?.where((a) => !a.archived)
        .map((a) => a.id)
        .toList();

    final body = accountsAsync.whenOrLoading(
      context: context,
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
        FHeaderAction(
          icon: FTooltip(
            tipBuilder: (_, _) => Text(l10n.accountsCreateAction),
            child: const Icon(FLucideIcons.plus),
          ),
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
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    final institutions = accounts
        .map((account) => account.institution?.trim())
        .whereType<String>()
        .where((institution) => institution.isNotEmpty)
        .toSet();
    final currencies = <String>{
      for (final account in accounts) account.currency.toUpperCase(),
      for (final balance in balances.values)
        for (final leg in balance.legs)
          if (leg.isFiatLike) leg.unit.toUpperCase(),
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(
        hPad,
        AppSpacing.s4,
        hPad,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _AccountsOverview(
          accountCount: accounts.length,
          institutionCount: institutions.length,
          currencyCount: currencies.length,
        ),
        const SizedBox(height: AppSpacing.s20),
        AccountsGroupedSections(
          accounts: accounts,
          balances: balances,
          selectedId: selectedId,
          heroEnabled: !inMasterDetail,
          allowExpansion: true,
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
        path: FinanceRoutes.wealthAccounts,
        selected: account.id,
      );
    } else {
      context.push(FinanceRoutes.wealthAccount(account.id));
    }
  }
}

class _AccountsOverview extends StatelessWidget {
  const _AccountsOverview({
    required this.accountCount,
    required this.institutionCount,
    required this.currencyCount,
  });

  final int accountCount;
  final int institutionCount;
  final int currencyCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.accountsOverviewTitle, style: context.strongTitleStyle),
            const SizedBox(height: AppSpacing.s14),
            Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    value: accountCount,
                    label: l10n.accountsOverviewAccountsLabel,
                  ),
                ),
                Expanded(
                  child: _OverviewMetric(
                    value: institutionCount,
                    label: l10n.accountsOverviewInstitutionsLabel,
                  ),
                ),
                Expanded(
                  child: _OverviewMetric(
                    value: currencyCount,
                    label: l10n.accountsOverviewCurrenciesLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            const _OverviewActions(),
          ],
        ),
      ),
    );
  }
}

class _OverviewActions extends StatelessWidget {
  const _OverviewActions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transfer = FButton(
      variant: FButtonVariant.primary,
      onPress: () => context.push(FinanceRoutes.transfer),
      prefix: const Icon(FLucideIcons.arrowLeftRight, size: AppIconSizes.sm),
      child: Text(l10n.accountsTransferAction),
    );
    final journal = FButton(
      variant: FButtonVariant.secondary,
      onPress: () => context.push(FinanceRoutes.journalEntries),
      prefix: const Icon(FLucideIcons.history, size: AppIconSizes.sm),
      child: Text(l10n.accountsJournalAction),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              transfer,
              const SizedBox(height: AppSpacing.s8),
              journal,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: transfer),
            const SizedBox(width: AppSpacing.s10),
            Expanded(child: journal),
          ],
        );
      },
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: context.strongTitleStyle),
        const SizedBox(height: AppSpacing.s2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.captionStyle,
        ),
      ],
    );
  }
}
