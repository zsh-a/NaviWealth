import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../domain/account_semantics.dart';
import 'account_labels.dart';

/// Semantic icon-grid picker for [AccountCategory].
///
/// Renders the four user-owned custody containers. Debt is created in the
/// liabilities flow and tangible/manual objects are created as assets.
///
/// Picking is the only interaction — the AccountSide is auto-derived
/// outside this widget, so the user never sees an "asset vs liability"
/// dropdown again.
class AccountCategoryPicker extends StatelessWidget {
  const AccountCategoryPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AccountCategory value;
  final ValueChanged<AccountCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final nominalColumns = constraints.maxWidth >= Breakpoints.mobile
            ? 4
            : 2;
        final labelSize = context.appTheme.type.label.fontSize!;
        final textScale =
            MediaQuery.textScalerOf(context).scale(labelSize) / labelSize;
        final maxColumns = (nominalColumns / textScale.clamp(1, 4))
            .floor()
            .clamp(1, nominalColumns);
        final rows = (kCustodyAccountCategories.length / maxColumns).ceil();
        final columns = (kCustodyAccountCategories.length / rows).ceil();
        final width =
            (constraints.maxWidth - AppSpacing.s10 * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.s10,
          runSpacing: AppSpacing.s10,
          children: [
            for (final c in kCustodyAccountCategories)
              SizedBox(
                width: width,
                child: _CategoryCard(
                  selected: c == value,
                  onTap: () => onChanged(c),
                  label: accountCategoryLabel(l10n, c),
                  hint: _hintFor(l10n, c),
                  icon: _iconFor(c),
                ),
              ),
          ],
        );
      },
    );
  }

  String _hintFor(AppLocalizations l10n, AccountCategory c) {
    return switch (c) {
      AccountCategory.cash => l10n.accountCategoryCashHint,
      AccountCategory.bank => l10n.accountCategoryBankHint,
      AccountCategory.broker => l10n.accountCategoryBrokerHint,
      AccountCategory.crypto => l10n.accountCategoryCryptoHint,
      AccountCategory.credit => l10n.accountCategoryCreditHint,
      AccountCategory.loan => l10n.accountCategoryLoanHint,
      AccountCategory.asset => l10n.accountCategoryAssetHint,
      AccountCategory.liability => l10n.accountCategoryLiabilityHint,
    };
  }

  IconData _iconFor(AccountCategory c) {
    return switch (c) {
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.selected,
    required this.onTap,
    required this.label,
    required this.hint,
    required this.icon,
  });

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final foreground = selected ? theme.accent.fg : theme.content.body;
    return AppChoiceTile(
      selected: selected,
      onPress: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIconTile(
            icon: icon,
            color: selected ? theme.accent.fg : theme.content.muted,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: theme.type.label.copyWith(color: foreground),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: AppSpacing.s4),
                      Icon(
                        FLucideIcons.check,
                        size: AppIconSizes.xs,
                        color: foreground,
                      ),
                    ],
                  ],
                ),
                Text(
                  hint,
                  style: theme.type.caption.copyWith(
                    color: theme.content.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
