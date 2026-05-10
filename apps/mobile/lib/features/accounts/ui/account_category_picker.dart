import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'account_labels.dart';

/// Semantic icon-grid picker for [AccountCategory].
///
/// Replaces the legacy `FSelect` dropdown. Renders 8 cards (cash / bank /
/// broker / crypto / credit / loan / asset / liability), each with an
/// icon + name + one-line affordance hint. The grid is responsive: 2
/// columns on phones, 4 on tablet+.
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
        // 2 columns under 480, 4 columns at tablet width.
        final cols = constraints.maxWidth >= 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            for (final c in AccountCategory.values)
              _CategoryCard(
                category: c,
                selected: c == value,
                onTap: () => onChanged(c),
                label: accountCategoryLabel(l10n, c),
                hint: _hintFor(l10n, c),
                icon: _iconFor(c),
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
      AccountCategory.cash => Icons.payments_outlined,
      AccountCategory.bank => Icons.account_balance_outlined,
      AccountCategory.broker => Icons.show_chart_outlined,
      AccountCategory.crypto => Icons.currency_bitcoin,
      AccountCategory.credit => Icons.credit_card_outlined,
      AccountCategory.loan => Icons.request_quote_outlined,
      AccountCategory.asset => Icons.inventory_2_outlined,
      AccountCategory.liability => Icons.south_east_outlined,
    };
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.label,
    required this.hint,
    required this.icon,
  });

  final AccountCategory category;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final border = selected
        ? colors.primary.withValues(alpha: 0.7)
        : colors.foreground.withValues(alpha: 0.06);
    final fill = selected
        ? colors.primary.withValues(alpha: 0.10)
        : colors.foreground.withValues(alpha: 0.02);
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const Spacer(),
              Text(
                label,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.primary : colors.foreground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: context.theme.typography.xs2.copyWith(
                  color: colors.mutedForeground,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
