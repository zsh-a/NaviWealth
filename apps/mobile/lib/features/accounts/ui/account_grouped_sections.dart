import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/shared/account_l10n.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../account_icon_catalog.dart';
import '../domain/account_balances.dart';
import 'account_labels.dart';

typedef AccountPressed = void Function(BuildContext context, Account account);

class AccountsGroupedSections extends StatelessWidget {
  const AccountsGroupedSections({
    super.key,
    required this.accounts,
    required this.balances,
    required this.onAccountPressed,
    this.selectedId,
    this.heroEnabled = false,
    this.allowExpansion = false,
  });

  final List<Account> accounts;
  final Map<String, AccountBalances> balances;
  final AccountPressed onAccountPressed;
  final String? selectedId;
  final bool heroEnabled;
  final bool allowExpansion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _groupByCategory(accounts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries)
          _AccountsSection(
            title: accountCategoryLabel(l10n, entry.key),
            accounts: entry.value,
            balances: balances,
            selectedId: selectedId,
            heroEnabled: heroEnabled,
            allowExpansion: allowExpansion,
            onAccountPressed: onAccountPressed,
          ),
      ],
    );
  }
}

Map<AccountCategory, List<Account>> _groupByCategory(List<Account> accounts) {
  const order = [
    AccountCategory.cash,
    AccountCategory.bank,
    AccountCategory.broker,
    AccountCategory.crypto,
    AccountCategory.credit,
    AccountCategory.loan,
    AccountCategory.asset,
    AccountCategory.liability,
  ];
  final out = <AccountCategory, List<Account>>{};
  for (final cat in order) {
    final group = accounts.where((a) => a.type == cat).toList();
    if (group.isEmpty) continue;
    out[cat] = group;
  }
  return out;
}

class _AccountsSection extends StatelessWidget {
  const _AccountsSection({
    required this.title,
    required this.accounts,
    required this.balances,
    required this.selectedId,
    required this.heroEnabled,
    required this.allowExpansion,
    required this.onAccountPressed,
  });

  final String title;
  final List<Account> accounts;
  final Map<String, AccountBalances> balances;
  final String? selectedId;
  final bool heroEnabled;
  final bool allowExpansion;
  final AccountPressed onAccountPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s12, 0, AppSpacing.s12, AppSpacing.s8),
            child: Text(
              title.toUpperCase(),
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SoftCard(
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  _AccountRow(
                    account: accounts[i],
                    balances:
                        balances[accounts[i].id] ??
                        AccountBalances.empty(accounts[i].id),
                    selected: accounts[i].id == selectedId,
                    heroEnabled: heroEnabled,
                    allowExpansion: allowExpansion,
                    onAccountPressed: onAccountPressed,
                  ),
                  if (i < accounts.length - 1) const FDivider(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.account,
    required this.balances,
    required this.selected,
    required this.heroEnabled,
    required this.allowExpansion,
    required this.onAccountPressed,
  });

  final Account account;
  final AccountBalances balances;
  final bool selected;
  final bool heroEnabled;
  final bool allowExpansion;
  final AccountPressed onAccountPressed;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final account = widget.account;
    final balances = widget.balances;
    final isExpandable = widget.allowExpansion && balances.isMultiUnit;
    final primaryLeg =
        balances.legFor(account.currency) ??
        (balances.legs.isNotEmpty ? balances.legs.first : null);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.selected
            ? colors.primary.withValues(alpha: AppOpacity.subtle)
            : Colors.transparent,
      ),
      child: Column(
        children: [
          FTile(
            onPress: () {
              if (isExpandable) {
                setState(() => _expanded = !_expanded);
              } else {
                widget.onAccountPressed(context, account);
              }
            },
            prefix: _AccountIconBadge(account: account),
            title: OptionalHero(
              tag: 'account-${account.id}-name',
              enabled: widget.heroEnabled,
              child: Text(
                localizedAccountName(AppLocalizations.of(context), account),
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            subtitle:
                account.institution != null && account.institution!.isNotEmpty
                ? Text(
                    account.institution!,
                    style: context.theme.typography.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (primaryLeg != null)
                      _PrimaryAmount(leg: primaryLeg)
                    else
                      Text(
                        '-',
                        style: context.theme.typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    if (balances.isMultiUnit)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s2),
                        child: Text(
                          _multiHint(balances),
                          style: context.theme.typography.xs2.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
                if (isExpandable)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: Icon(
                      _expanded
                          ? FLucideIcons.chevronUp
                          : FLucideIcons.chevronDown,
                      size: AppIconSizes.h18,
                      color: colors.mutedForeground.withValues(alpha: AppOpacity.prominent),
                    ),
                  ),
              ],
            ),
          ),
          if (isExpandable && _expanded)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 64,
                end: 14,
                bottom: 10,
              ),
              child: Column(
                children: [
                  for (final leg in balances.legs)
                    if (leg.unit != account.currency ||
                        balances.legs.length > 1)
                      _SubLegRow(leg: leg),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _multiHint(AccountBalances balances) {
    final units = balances.legs.map((l) => l.unit).toList();
    if (units.length <= 3) return units.join(' · ');
    return '${units.take(2).join(' · ')} · +${units.length - 2}';
  }
}

class _AccountIconBadge extends StatelessWidget {
  const _AccountIconBadge({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = _accountAccent(context, account);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(
        resolveAccountIcon(account.icon) ?? _iconFor(account.type),
        size: AppIconSizes.h18,
        color: accent == colors.mutedForeground
            ? colors.mutedForeground
            : accent,
      ),
    );
  }

  Color _accountAccent(BuildContext context, Account account) {
    final color = account.color;
    if (color == null || color.isEmpty) {
      return context.theme.colors.mutedForeground;
    }
    final hex = color.startsWith('#') ? color.substring(1) : color;
    if (hex.length != 6) return context.theme.colors.mutedForeground;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return context.theme.colors.mutedForeground;
    return Color(0xFF000000 | value);
  }

  IconData _iconFor(AccountCategory cat) {
    return switch (cat) {
      AccountCategory.cash => FLucideIcons.banknote,
      AccountCategory.bank => FLucideIcons.landmark,
      AccountCategory.broker => FLucideIcons.chartLine,
      AccountCategory.crypto => FLucideIcons.bitcoin,
      AccountCategory.credit => FLucideIcons.creditCard,
      AccountCategory.loan => FLucideIcons.fileText,
      AccountCategory.asset => FLucideIcons.package,
      AccountCategory.liability => FLucideIcons.arrowDownRight,
    };
  }
}

class _PrimaryAmount extends ConsumerWidget {
  const _PrimaryAmount({required this.leg});

  final AccountBalanceLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SignedMoneyText(
      amount: leg.units,
      unit: leg.unit,
      formatters: context.formatters(ref),
      showPositiveSign: false,
      colorBySign: false,
      style: context.theme.typography.sm.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _SubLegRow extends ConsumerWidget {
  const _SubLegRow({required this.leg});

  final AccountBalanceLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppFormatters.assetCode(leg.unit),
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SignedMoneyText(
            amount: leg.units,
            unit: leg.unit,
            formatters: context.formatters(ref),
            showPositiveSign: false,
            colorBySign: false,
            style: context.theme.typography.sm,
          ),
        ],
      ),
    );
  }
}
