part of 'expense_report_sections.dart';

class _Pie extends StatelessWidget {
  const _Pie({
    required this.report,
    required this.categoryById,
    required this.slices,
  });

  final ExpenseReport report;
  final Map<String, ExpenseCategory> categoryById;
  final List<ExpenseReportPieSlice> slices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chartSlices = <Slice>[
      for (final slice in slices)
        Slice(
          label: slice.labelKey,
          value: slice.breakdown.total.amount.toDouble(),
          colorOverride: slice.color,
          meta: slice.breakdown,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSize = constraints.maxWidth < Breakpoints.mobile
            ? 208.0
            : 224.0;
        final size = constraints.maxWidth.clamp(168.0, maxSize).toDouble();
        return Align(
          alignment: Alignment.center,
          child: SizedBox.square(
            dimension: size,
            child: NwPieChart(
              slices: chartSlices,
              hole: 0.66,
              minLabelPercent: 7,
              drillDown: SliceDrillDown((slice) {
                final breakdown = slice.meta;
                if (breakdown is! CategoryBreakdown) return;
                _openSpendingBreakdown(
                  context,
                  report: report,
                  breakdown: breakdown,
                  categoryById: categoryById,
                );
              }),
              semanticLabel: l10n.expenseReportCategoryShare,
            ),
          ),
        );
      },
    );
  }
}

class _PieLegend extends StatelessWidget {
  const _PieLegend({
    required this.report,
    required this.categoryById,
    required this.slices,
  });

  final ExpenseReport report;
  final Map<String, ExpenseCategory> categoryById;
  final List<ExpenseReportPieSlice> slices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = report.total.amount.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices)
          _LegendRow(
            color: slice.color,
            label: slice.labelKey,
            valueInBase: slice.breakdown.total.amount.toDouble(),
            currencyCode: report.baseCurrency,
            percent: total == 0
                ? 0
                : slice.breakdown.total.amount.toDouble() / total,
            onTap: () => _openSpendingBreakdown(
              context,
              report: report,
              breakdown: slice.breakdown,
              categoryById: categoryById,
            ),
          ),
        if (slices.isEmpty)
          Text(l10n.expenseReportNoExpenses, style: context.captionStyle),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.valueInBase,
    required this.currencyCode,
    required this.percent,
    required this.onTap,
  });

  final Color color;
  final String label;
  final double valueInBase;
  final String currencyCode;
  final double percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s6,
          horizontal: AppSpacing.s4,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.s12,
              height: AppSpacing.s12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.theme.typography.body.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${(percent * 100).toStringAsFixed(1)}%',
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            MoneyText(
              amount: valueInBase,
              currencyCode: currencyCode,
              compact: true,
            ),
            const SizedBox(width: AppSpacing.s4),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: context.theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
