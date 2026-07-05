part of 'expense_report_sections.dart';

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.breakdown,
    required this.categoryById,
    required this.baseCurrency,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = categoryById[breakdown.expenseAccountId];
    final accent =
        category?.expenseAccentColor(context) ?? context.theme.colors.primary;
    return FTappable(
      onPress: () => showAppFormSheet<void>(
        context: context,
        builder: (ctx) => _CategoryDrillDown(
          breakdown: breakdown,
          categoryById: categoryById,
          baseCurrency: baseCurrency,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.s32,
              height: AppSpacing.s32,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Icon(
                  category?.iconData ?? FLucideIcons.banknote,
                  size: AppIconSizes.md,
                  color: accent.withValues(alpha: AppOpacity.prominent),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _categoryLabel(
                      l10n,
                      category,
                      l10n.expenseReportUncategorized,
                    ),
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    l10n.expenseReportItemCount(breakdown.items.length),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            MoneyText(
              amount: breakdown.total.amount.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
              style: context.strongLabelStyle,
            ),
          ],
        ),
      ),
    );
  }
}
