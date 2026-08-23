import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/account_balances_provider.dart';
import '../domain/account_balances.dart';
import 'account_labels.dart';

/// Read-first account surface. Mutating account metadata is deliberately a
/// secondary action so tapping a row never drops the user into a form.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({
    super.key,
    required this.accountId,
    this.cashAssetId,
  });

  final String accountId;

  /// When this account page is reached through a cash asset, expose the
  /// balance editor alongside transfer. Account metadata editing remains a
  /// separate header action.
  final String? cashAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final balancesAsync = ref.watch(accountBalancesByIdProvider);
    final journalAsync = ref.watch(journalEntriesWithPostingsStreamProvider);

    final accounts = accountsAsync.value ?? const <Account>[];
    final account = accounts.where((item) => item.id == accountId).firstOrNull;

    return ObjectDetailScaffold(
      title: account?.name ?? l10n.navAccounts,
      // Hero pair for the account edit form (`account-{id}-name`). The
      // accounts list row no longer carries the other side — it opens this
      // page through AppContainerTransform instead — so no `enabled` gate.
      titleWidget: account == null
          ? null
          : OptionalHero(
              tag: 'account-${account.id}-name',
              child: Text(account.name),
            ),
      actions: [
        if (account != null)
          AppHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            semanticsLabel: l10n.accountDetailEditAction,
            onPress: () =>
                context.push(FinanceRoutes.wealthAccountEdit(account.id)),
          ),
      ],
      childPad: false,
      child: accountsAsync.when(
        loading: () => const AssetDetailSkeleton(),
        error: (error, stackTrace) => kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () => ref.invalidate(accountsStreamProvider),
        ),
        data: (_) {
          if (account == null) {
            return Center(child: Text(l10n.accountDetailNotFound));
          }
          return _AccountDetailBody(
            account: account,
            accounts: accounts,
            cashAssetId: cashAssetId,
            balances:
                balancesAsync.value?[account.id] ??
                AccountBalances.empty(account.id),
            activity: journalAsync.value ?? const <JournalEntryWithPostings>[],
          );
        },
      ),
    );
  }
}

class _AccountDetailBody extends ConsumerWidget {
  const _AccountDetailBody({
    required this.account,
    required this.accounts,
    required this.cashAssetId,
    required this.balances,
    required this.activity,
  });

  final Account account;
  final List<Account> accounts;
  final String? cashAssetId;
  final AccountBalances balances;
  final List<JournalEntryWithPostings> activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final recent = activity
        .where(
          (entry) =>
              entry.postings.any((posting) => posting.accountId == account.id),
        )
        .take(6)
        .toList(growable: false);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _BalanceCard(
          account: account,
          balances: balances,
          cashAssetId: cashAssetId,
        ),
        const SizedBox(height: AppSpacing.s12),
        _FactsCard(account: account),
        const SizedBox(height: AppSpacing.s20),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.accountDetailRecentActivityTitle,
                style: context.strongTitleStyle,
              ),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => context.push(FinanceRoutes.journalEntries),
              child: Text(l10n.dashboardActivityPreviewViewAll),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s20),
            child: Text(
              l10n.accountDetailNoActivity,
              style: context.captionStyle,
              textAlign: TextAlign.center,
            ),
          )
        else
          SoftCard.raised(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: Column(
                children: [
                  for (var index = 0; index < recent.length; index++) ...[
                    _ActivityRow(
                      entry: recent[index],
                      account: account,
                      accounts: accounts,
                      formatters: formatters,
                    ),
                    if (index < recent.length - 1) const FDivider(),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({
    required this.account,
    required this.balances,
    required this.cashAssetId,
  });

  final Account account;
  final AccountBalances balances;
  final String? cashAssetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    // With an existing cash asset the button edits it; without one it
    // opens the cash form preselected on this account, so a fresh
    // account is never a dead end for its first balance.
    Widget adjustBalanceButton() => FButton(
      key: const Key('account-adjust-cash-balance'),
      variant: FButtonVariant.secondary,
      onPress: () => context.push(
        cashAssetId == null
            ? FinanceRoutes.wealthNewCashForAccount(account.id)
            : FinanceRoutes.wealthAssetEdit(cashAssetId!),
      ),
      prefix: Icon(
        cashAssetId == null ? FLucideIcons.plus : FLucideIcons.pencil,
        size: AppIconSizes.sm,
      ),
      child: Text(
        cashAssetId == null
            ? l10n.accountDetailAddBalanceAction
            : l10n.accountDetailAdjustBalanceAction,
      ),
    );
    Widget transferButton() => FButton(
      variant: FButtonVariant.primary,
      onPress: () =>
          context.push(FinanceRoutes.transferFromAccount(account.id)),
      prefix: const Icon(FLucideIcons.arrowLeftRight, size: AppIconSizes.sm),
      child: Text(l10n.accountDetailTransferAction),
    );
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.accountDetailBalanceTitle, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s8),
            if (balances.legs.isEmpty)
              Text('—', style: TypographyTokens.displayMedium)
            else
              for (final leg in balances.legs)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: SignedMoneyText(
                      amount: leg.units,
                      unit: leg.unit,
                      formatters: formatters,
                      showPositiveSign: false,
                      colorBySign: false,
                      style: leg.unit == account.currency
                          ? TypographyTokens.displayMedium
                          : context.strongTitleStyle,
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.s16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < Breakpoints.dialogMax) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      adjustBalanceButton(),
                      const SizedBox(height: AppSpacing.s8),
                      transferButton(),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: adjustBalanceButton()),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(child: transferButton()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final institution = account.institution?.trim();
    final number = account.accountNumber?.trim();
    final note = account.note?.trim();
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          children: [
            _FactRow(
              label: l10n.accountDetailTypeLabel,
              value: accountCategoryLabel(l10n, account.type),
            ),
            _FactRow(
              label: l10n.accountDetailCurrencyLabel,
              value: account.currency.toUpperCase(),
            ),
            if (institution != null && institution.isNotEmpty)
              _FactRow(
                label: l10n.accountDetailInstitutionLabel,
                value: institution,
              ),
            if (number != null && number.isNotEmpty)
              _FactRow(
                label: l10n.accountDetailNumberLabel,
                value: _maskedNumber(number),
              ),
            if (note != null && note.isNotEmpty)
              _FactRow(label: l10n.accountDetailNotesLabel, value: note),
          ],
        ),
      ),
    );
  }

  String _maskedNumber(String value) {
    if (value.length <= 4) return value;
    return '•••• ${value.substring(value.length - 4)}';
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: context.captionStyle)),
          const SizedBox(width: AppSpacing.s16),
          Flexible(
            child: Text(
              value,
              style: context.bodyCaptionStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.entry,
    required this.account,
    required this.accounts,
    required this.formatters,
  });

  final JournalEntryWithPostings entry;
  final Account account;
  final List<Account> accounts;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final posting = entry.postings
        .where((item) => item.accountId == account.id)
        .firstOrNull;
    return AppTappable(
      onPress: () => context.push(
        FinanceRoutes.activityEntry(entry.entry.id),
        extra: ActivityEntryDetailArgs(
          entry: entry,
          accountsById: {for (final item in accounts) item.id: item},
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.entry.narration,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.labelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    formatters.date(entry.entry.date),
                    style: context.microCaptionStyle,
                  ),
                ],
              ),
            ),
            if (posting != null) ...[
              const SizedBox(width: AppSpacing.s12),
              SignedMoneyText(
                amount: posting.units,
                unit: posting.unit,
                formatters: formatters,
                style: context.mediumLabelStyle,
              ),
            ],
            const SizedBox(width: AppSpacing.s4),
            const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
          ],
        ),
      ),
    );
  }
}
