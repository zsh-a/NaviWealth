part of 'expense_report_sections.dart';

class _CategoryDrillDown extends StatelessWidget {
  const _CategoryDrillDown({
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
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final category = categoryById[breakdown.expenseAccountId];
    final entries = [...breakdown.items]
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s8,
            AppSpacing.s16,
            AppSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    category?.iconData ?? FLucideIcons.banknote,
                    color: context.theme.colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _categoryLabel(
                        l10n,
                        category,
                        l10n.expenseReportUncategorized,
                      ),
                      style: context.rowTitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  MoneyText(
                    amount: breakdown.total.amount.toDouble(),
                    currencyCode: baseCurrency,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.expenseReportItemCount(entries.length),
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s12),
              const FDivider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final exp = entries[i];
                    return _ExpenseLine(
                      expense: exp,
                      formatter: formatter,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        context.push(FinanceRoutes.expense(exp.id));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseLine extends StatelessWidget {
  const _ExpenseLine({
    required this.expense,
    required this.formatter,
    this.onTap,
  });

  final Expense expense;
  final AppFormatters formatter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.note ?? formatter.date(expense.tradeDate),
                    style: context.labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    formatter.date(expense.tradeDate),
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Text(
              formatter.currency(expense.amount, code: expense.currency),
              style: context.strongLabelStyle.copyWith(
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
