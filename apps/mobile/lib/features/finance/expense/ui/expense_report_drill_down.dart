part of 'expense_report_sections.dart';

class _CategoryDrillDown extends StatelessWidget {
  const _CategoryDrillDown({
    required this.breakdown,
    required this.categoryById,
    required this.baseCurrency,
    this.otherSource,
  });

  final CategoryBreakdown breakdown;
  final Map<String, Account> categoryById;
  final String baseCurrency;

  /// Pre-collapse tail rows when drilling into the pie "Other" bucket.
  final List<CategoryBreakdown>? otherSource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final category = categoryById[breakdown.expenseAccountId];
    final isOther = breakdown.expenseAccountId == kExpenseReportPieOtherId;
    final groupedOther = isOther
        ? (otherSource ?? const <CategoryBreakdown>[])
        : null;

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
                    isOther
                        ? FLucideIcons.ellipsis
                        : (category?.iconData ?? FLucideIcons.banknote),
                    color: expenseReportSliceColor(
                      context,
                      expenseAccountId: breakdown.expenseAccountId,
                      account: category,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _breakdownLabel(l10n, breakdown, categoryById),
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
                isOther && groupedOther != null
                    ? l10n.expenseReportOtherCategoryCount(groupedOther.length)
                    : l10n.expenseReportItemCount(breakdown.items.length),
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s12),
              const FDivider(),
              Expanded(
                child:
                    isOther && groupedOther != null && groupedOther.isNotEmpty
                    ? _OtherGroupedList(
                        groups: groupedOther,
                        categoryById: categoryById,
                        baseCurrency: baseCurrency,
                        formatter: formatter,
                        scrollController: scrollController,
                      )
                    : Builder(
                        builder: (ctx) {
                          final entries = [
                            ...breakdown.items,
                          ]..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
                          return ListView.builder(
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

/// "Other" drill-down: one section per original category so long-tail
/// spend stays discoverable after the pie roll-up.
class _OtherGroupedList extends StatelessWidget {
  const _OtherGroupedList({
    required this.groups,
    required this.categoryById,
    required this.baseCurrency,
    required this.formatter,
    required this.scrollController,
  });

  final List<CategoryBreakdown> groups;
  final Map<String, Account> categoryById;
  final String baseCurrency;
  final AppFormatters formatter;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[];
    for (final group in groups) {
      final account = categoryById[group.expenseAccountId];
      final accent = expenseReportSliceColor(
        context,
        expenseAccountId: group.expenseAccountId,
        account: account,
      );
      final entries = [...group.items]
        ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
      children.add(
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.s12,
            bottom: AppSpacing.s4,
          ),
          child: Row(
            children: [
              Container(
                width: AppSpacing.s10,
                height: AppSpacing.s10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  _breakdownLabel(l10n, group, categoryById),
                  style: context.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MoneyText(
                amount: group.total.amount.toDouble(),
                currencyCode: baseCurrency,
                compact: true,
                style: context.captionStyle,
              ),
            ],
          ),
        ),
      );
      children.add(
        Text(
          l10n.expenseReportItemCount(entries.length),
          style: context.captionStyle,
        ),
      );
      for (final exp in entries) {
        children.add(
          _ExpenseLine(
            expense: exp,
            formatter: formatter,
            onTap: () {
              Navigator.of(context).pop();
              context.push(FinanceRoutes.expense(exp.id));
            },
          ),
        );
      }
    }

    return ListView(controller: scrollController, children: children);
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
