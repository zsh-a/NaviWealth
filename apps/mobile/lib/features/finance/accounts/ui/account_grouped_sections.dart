import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/l10n/account_l10n.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../shared/ui/account_color.dart';
import '../../shared/ui/account_icon_catalog.dart';
import '../domain/account_balances.dart';
import '../domain/account_semantics.dart';
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
  final grouped = <AccountCategory, List<Account>>{};
  for (final account in accounts) {
    grouped.putIfAbsent(account.type, () => []).add(account);
  }

  final out = <AccountCategory, List<Account>>{};
  for (final cat in kCustodyAccountCategories) {
    final group = grouped[cat];
    if (group == null) continue;
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
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final background = isDark
        ? colors.card.withValues(alpha: AppOpacity.muted)
        : ColorPalette.surfaceRaised;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              0,
              AppSpacing.s4,
              AppSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.mutedLabelStyle)),
                Text(
                  l10n.accountsCategoryCount(accounts.length),
                  style: context.microCaptionStyle,
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
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
                    if (i < accounts.length - 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpacing.s48,
                        ),
                        child: SizedBox(
                          height: AppSpacing.hairline,
                          child: ColoredBox(
                            color: colors.border.withValues(
                              alpha: AppOpacity.faint,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
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
    final primaryLeg =
        balances.legFor(account.currency) ??
        (balances.legs.isNotEmpty ? balances.legs.first : null);
    final detailLegs = primaryLeg == null
        ? balances.legs
        : balances.legs
              .where((leg) => leg.unit != primaryLeg.unit)
              .toList(growable: false);
    final isExpandable = widget.allowExpansion && detailLegs.isNotEmpty;
    final accountName = localizedAccountName(
      AppLocalizations.of(context),
      account,
    );
    final institution = account.institution?.trim();
    final metadata = [
      if (institution != null && institution.isNotEmpty) institution,
      account.currency.toUpperCase(),
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.selected
            ? colors.primary.withValues(alpha: AppOpacity.whisper)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: accountName,
                    child: AppTappable(
                      onPress: () => widget.onAccountPressed(context, account),
                      child: Row(
                        children: [
                          _AccountIconMark(
                            account: account,
                            selected: widget.selected,
                          ),
                          const SizedBox(width: AppSpacing.s16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OptionalHero(
                                  tag: 'account-${account.id}-name',
                                  enabled: widget.heroEnabled,
                                  child: Text(
                                    accountName,
                                    style: context.labelStyle.copyWith(
                                      color: colors.foreground,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s2),
                                Text(
                                  metadata,
                                  style: context.captionStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 128),
                            child: primaryLeg == null
                                ? Text(
                                    '—',
                                    textAlign: TextAlign.end,
                                    style: context.bodyCaptionStyle,
                                  )
                                : _PrimaryAmount(leg: primaryLeg),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isExpandable)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppSpacing.s4,
                    ),
                    child: AppTappable(
                      onPress: () => setState(() => _expanded = !_expanded),
                      child: SizedBox(
                        width: AppSpacing.s32,
                        height: AppSpacing.s32,
                        child: Icon(
                          _expanded
                              ? FLucideIcons.chevronUp
                              : FLucideIcons.chevronDown,
                          size: AppIconSizes.h18,
                          color: colors.mutedForeground.withValues(
                            alpha: AppOpacity.prominent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isExpandable && _expanded)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.s48,
                end: AppSpacing.s2,
                bottom: AppSpacing.s10,
              ),
              child: Column(
                children: [for (final leg in detailLegs) _SubLegRow(leg: leg)],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountIconMark extends StatelessWidget {
  const _AccountIconMark({required this.account, required this.selected});

  final Account account;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = _accountAccent(context, account);
    return SizedBox(
      width: AppSpacing.s32,
      height: AppSpacing.s32,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Icon(
          resolveAccountIcon(account.icon) ?? _iconFor(account.type),
          size: AppIconSizes.md,
          color: selected
              ? colors.primary
              : accent.withValues(alpha: AppOpacity.prominent),
        ),
      ),
    );
  }

  Color _accountAccent(BuildContext context, Account account) {
    return parseAccountColor(account.color) ??
        context.theme.colors.mutedForeground;
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
      style: context.labelStyle,
      textAlign: TextAlign.end,
    );
  }
}

class _SubLegRow extends ConsumerWidget {
  const _SubLegRow({required this.leg});

  final AccountBalanceLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatters = context.formatters(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppFormatters.assetCode(leg.unit),
              style: context.captionMediumStyle,
            ),
          ),
          Text(
            formatters.number(
              leg.units.toDouble(),
              decimalDigits: _balanceQuantityDigits(leg.units),
            ),
            style: context.theme.typography.body.sm.copyWith(
              fontFeatures: TypographyTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

int _balanceQuantityDigits(Decimal quantity) {
  final value = quantity.toDouble().abs();
  if (value == 0) return 0;
  if (value >= 100) return 0;
  if (value >= 1) return 2;
  return 4;
}
