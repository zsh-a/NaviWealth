import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/data/domain/enums.dart';
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
        final aspectRatio = cols == 2 ? 1.35 : 1.6;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: aspectRatio,
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
        ? colors.primary.withValues(alpha: AppOpacity.strong)
        : colors.foreground.withValues(alpha: AppOpacity.faint);
    final fill = selected
        ? colors.primary.withValues(alpha: AppOpacity.subtle)
        : colors.foreground.withValues(alpha: AppOpacity.whisper);
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s12, AppSpacing.s12, AppSpacing.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: AppOpacity.medium),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSizes.h18, color: iconColor),
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
              const SizedBox(height: AppSpacing.s2),
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
