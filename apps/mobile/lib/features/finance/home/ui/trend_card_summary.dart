part of 'trend_card.dart';

class _TrendSummary extends ConsumerWidget {
  const _TrendSummary({required this.trend});

  final DashboardTrend trend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trend.points.length < 2) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final first = trend.points.first;
    final last = trend.points.last;
    final delta = last.netWorth.amount - first.netWorth.amount;
    final firstValue = first.netWorth.amount.toDouble();
    final ratio = firstValue.abs() <= 0
        ? null
        : delta.toDouble() / firstValue.abs();
    final hidden = AmountPrivacyScope.isHiddenOf(context);
    final rangeLabel = _formatDateRange(
      formatters,
      first.asOf.toLocal(),
      last.asOf.toLocal(),
    );
    final colors = context.theme.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardTrendMetricCurrent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.microCaptionStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              if (hidden)
                AmountPrivacyPlaceholder(
                  density: AmountPrivacyPlaceholderDensity.title,
                  style: TypographyTokens.numericTitleStrong,
                )
              else
                Text(
                  formatters.compactCurrency(
                    last.netWorth.amount,
                    code: trend.baseCurrency,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypographyTokens.numericTitleStrong.copyWith(
                    color: colors.foreground,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.s6,
                runSpacing: AppSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DeltaText(
                    value: delta.toDouble(),
                    format: DeltaFormat.currency,
                    currencyCode: trend.baseCurrency,
                    fractionDigits: 0,
                    showIcon: false,
                    style: TypographyTokens.numericBodyStrong,
                  ),
                  if (ratio != null && !hidden)
                    Text(
                      formatters.signedPercent(ratio, decimalDigits: 1),
                      style: context.captionMediumStyle.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                rangeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: context.microCaptionStyle.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateRange(
    AppFormatters formatters,
    DateTime start,
    DateTime end,
  ) {
    final sameYear = start.year == end.year;
    final startLabel = sameYear
        ? formatters.monthDay(start)
        : formatters.date(start);
    final endLabel = sameYear ? formatters.monthDay(end) : formatters.date(end);
    return '$startLabel - $endLabel';
  }
}
