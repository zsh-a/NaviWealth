part of '../analytics_page.dart';

class _CashFlowTrendCard extends ConsumerWidget {
  const _CashFlowTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(
      cashFlowSummaryProvider(
        const CashFlowSummaryRequest(period: CashFlowPeriod.month),
      ),
    );
    return SoftCard(
      borderless: true,
      level: SoftCardLevel.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.analyticsCashFlowTrendTitle,
              style: context.theme.typography.body.md,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.analyticsCashFlowTrendSubtitle,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s16),
            async.when(
              loading: () => const SizedBox(
                height: AppChartHeights.card,
                child: Center(child: FCircularProgress()),
              ),
              error: (error, _) => AppEmptyState.error(
                title: l10n.analyticsCashFlowTrendLoadError,
                message: '$error',
                icon: FLucideIcons.circleX,
              ),
              data: (summary) {
                final now = ref.watch(cashFlowNowProvider);
                final months = _cashFlowMonths(summary, now: now);
                return _CashFlowTrendContent(summary: summary, months: months);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CashFlowTrendContent extends ConsumerWidget {
  const _CashFlowTrendContent({required this.summary, required this.months});

  final CashFlowSummary summary;
  final List<_CashFlowMonth> months;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final hasData = months.any(
      (m) => m.inflow != Decimal.zero || m.outflow != Decimal.zero,
    );
    final average = months.isEmpty
        ? Decimal.zero
        : (months.fold(Decimal.zero, (sum, m) => sum + m.net) /
                  Decimal.fromInt(months.length))
              .toDecimal(scaleOnInfinitePrecision: 6);
    final current = months.isEmpty ? null : months.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasData)
          const SizedBox(
            height: AppChartHeights.card,
            child: EmptyChartPlaceholder(icon: FLucideIcons.chartColumn),
          )
        else
          SizedBox(
            height: AppChartHeights.card,
            child: NwBarChart(
              series: [
                CategorySeries(
                  name: l10n.analyticsCashFlowTrendNetSeries,
                  data: [
                    for (final month in months)
                      CategoryDatum(
                        label: month.shortLabel,
                        value: month.net.toDouble(),
                        colorOverride: month.net.sign < 0
                            ? colors.destructive
                            : colors.primary,
                      ),
                  ],
                ),
              ],
              yAxis: ValueAxis.currency(
                currencyCode: summary.baseCurrency,
                maxLabels: 4,
              ),
              semanticLabel: l10n.analyticsCashFlowTrendSemantic,
            ),
          ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s8,
          children: [
            _MetricReadout(
              label: l10n.analyticsCashFlowTrendAverageNet,
              value: _formatSignedCurrency(
                formatters,
                average,
                summary.baseCurrency,
              ),
            ),
            if (current != null) ...[
              _MetricReadout(
                label: l10n.analyticsCashFlowTrendInflow,
                value: formatters.currency(
                  current.inflow,
                  code: summary.baseCurrency,
                ),
              ),
              _MetricReadout(
                label: l10n.analyticsCashFlowTrendOutflow,
                value: formatters.currency(
                  current.outflow,
                  code: summary.baseCurrency,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CashFlowMonth {
  const _CashFlowMonth({
    required this.key,
    required this.inflow,
    required this.outflow,
    required this.net,
  });

  final String key;
  final Decimal inflow;
  final Decimal outflow;
  final Decimal net;

  String get shortLabel => key.substring(5);
}

List<_CashFlowMonth> _cashFlowMonths(
  CashFlowSummary summary, {
  required DateTime now,
}) {
  final keys = _recentMonthKeys(now.toUtc(), 6);
  return [
    for (final key in keys)
      _CashFlowMonth(
        key: key,
        inflow: _sumMonthlyCash(summary, key, positive: true),
        outflow: _sumMonthlyCash(summary, key, positive: false),
        net: _sumMonthlyNet(summary, key),
      ),
  ];
}

Decimal _sumMonthlyNet(CashFlowSummary summary, String key) {
  return summary.buckets
      .where(
        (bucket) =>
            bucket.key == key && kOperatingCashFlowKinds.contains(bucket.kind),
      )
      .fold(Decimal.zero, (sum, bucket) => sum + bucket.totalInBase.amount);
}

Decimal _sumMonthlyCash(
  CashFlowSummary summary,
  String key, {
  required bool positive,
}) {
  return summary.buckets
      .where(
        (bucket) =>
            bucket.key == key && kOperatingCashFlowKinds.contains(bucket.kind),
      )
      .fold(Decimal.zero, (sum, bucket) {
        final amount = bucket.totalInBase.amount;
        if (positive && amount > Decimal.zero) return sum + amount;
        if (!positive && amount < Decimal.zero) return sum + amount.abs();
        return sum;
      });
}

List<String> _recentMonthKeys(DateTime now, int count) {
  return [
    for (var offset = count - 1; offset >= 0; offset--)
      _monthKey(_addMonths(now, -offset)),
  ];
}

DateTime _addMonths(DateTime date, int delta) {
  final monthIndex = date.year * 12 + date.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  return DateTime.utc(year, month, 1);
}

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

String _formatSignedCurrency(
  AppFormatters formatters,
  Decimal amount,
  String currency,
) {
  final value = formatters.currency(amount, code: currency);
  return amount.sign > 0 ? '+$value' : value;
}
