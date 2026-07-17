part of 'expense_report_sections.dart';

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.breakdown,
    required this.categoryById,
    required this.baseCurrency,
    this.otherSource,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final String baseCurrency;

  /// When [breakdown] is the pie "Other" roll-up, the original tail rows
  /// (still sorted descending) so drill-down can group by category.
  final List<CategoryBreakdown>? otherSource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = categoryById[breakdown.expenseAccountId];
    final isOther = breakdown.expenseAccountId == kExpenseReportPieOtherId;
    final accent = expenseReportSliceColor(
      context,
      expenseAccountId: breakdown.expenseAccountId,
      account: category,
    );
    return FTappable(
      onPress: () => showAppFormSheet<void>(
        context: context,
        builder: (ctx) => _CategoryDrillDown(
          breakdown: breakdown,
          categoryById: categoryById,
          baseCurrency: baseCurrency,
          otherSource: otherSource,
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
                  isOther
                      ? FLucideIcons.ellipsis
                      : (category?.iconData ?? FLucideIcons.banknote),
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
                    _breakdownLabel(l10n, breakdown, categoryById),
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    isOther && otherSource != null
                        ? l10n.expenseReportOtherCategoryCount(
                            otherSource!.length,
                          )
                        : l10n.expenseReportItemCount(breakdown.items.length),
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
