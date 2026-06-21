import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/format/formatters.dart';
import '../../core/format/providers.dart';
import '../../design_system/design_system.dart';
import '../../features/cashflow/data/cash_flow_providers.dart';
import '../../features/cashflow/domain/cash_flow_aggregator.dart';
import '../../features/cashflow/domain/home_cash_flow_metrics.dart';
import '../../features/fire/data/fire_providers.dart';
import '../../features/fire/domain/fire_state.dart';
import '../../features/home/data/dashboard_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import 'domain/equity_classification.dart';
import 'ui/benchmark/benchmark_comparison_card.dart';
import 'ui/equity_allocation_section.dart';
import 'ui/risk_alert_panel.dart';

export 'ui/dimension_segment.dart' show DimensionSegment;
export 'ui/equity_allocation_section.dart' show EquityAllocationContent;
export 'ui/equity_bucket_sheet.dart'
    show EquityBucketHoldingsSheet, localizeBucketLabel;

/// Planning analytics surface. The page owns layout and active dimension
/// selection; heavy equity, risk, and benchmark sections live in `ui/`.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  EquityAllocationDimension _dimension = EquityAllocationDimension.sector;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPageScaffold(
      title: l10n.analyticsAppBarTitle,
      childPad: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !Breakpoints.isMobile(constraints.maxWidth);
          final basePadding = isWide
              ? const EdgeInsets.all(AppSpacing.s24)
              : const EdgeInsets.all(AppSpacing.s16);
          return ListView(
            padding: basePadding.copyWith(
              bottom:
                  basePadding.bottom +
                  64 +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _AnalyticsOverviewGrid(isWide: isWide),
              const SizedBox(height: AppSpacing.s24),
              const ResponsiveTwoColumn(
                left: _CashFlowTrendCard(),
                right: _FireProgressCard(),
              ),
              const SizedBox(height: AppSpacing.s24),
              ResponsiveTwoColumn(
                left: AnalyticsEquityColumn(
                  dimension: _dimension,
                  onDimensionChanged: (d) => setState(() => _dimension = d),
                ),
                right: const _RiskAndBenchmarkColumn(),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
              style: context.theme.typography.md,
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

class _FireProgressCard extends ConsumerWidget {
  const _FireProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(fireStateProvider);
    return SoftCard(
      borderless: true,
      level: SoftCardLevel.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.analyticsFireProgressTitle,
              style: context.theme.typography.md,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.analyticsFireProgressSubtitle,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s16),
            async.when(
              loading: () => const SizedBox(
                height: AppChartHeights.card,
                child: Center(child: FCircularProgress()),
              ),
              error: (error, _) => AppEmptyState.error(
                title: l10n.analyticsFireProgressLoadError,
                message: '$error',
                icon: FLucideIcons.circleX,
              ),
              data: (state) => _FireProgressContent(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

class _FireProgressContent extends ConsumerWidget {
  const _FireProgressContent({required this.state});

  final FireState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    if (!state.isConfigured) {
      return AppEmptyState(
        icon: FLucideIcons.flag,
        title: l10n.analyticsFireProgressNotConfiguredTitle,
        message: l10n.analyticsFireProgressNotConfiguredBody,
      );
    }

    final target = state.plan.targetNetWorthMoney;
    final progress = target.amount == Decimal.zero
        ? 0.0
        : (state.investableAssets.amount / target.amount)
              .toDecimal(scaleOnInfinitePrecision: 6)
              .toDouble()
              .clamp(0.0, 1.0);
    final eta = state.fireEtaMonths;
    final withdrawal = state.finiteWithdrawalRate;
    final cashMonths = state.cashBucketMonthsRounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FDeterminateProgress(value: progress),
        const SizedBox(height: AppSpacing.s8),
        Text(
          l10n.analyticsFireProgressPercent(
            formatters.percent(progress, decimalDigits: 1),
          ),
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s8,
          children: [
            _MetricReadout(
              label: l10n.analyticsFireProgressInvestable,
              value: formatters.currency(
                state.investableAssets.amount,
                code: state.baseCurrency,
              ),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressTarget,
              value: formatters.currency(target.amount, code: target.currency),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressWithdrawalRate,
              value: withdrawal == null
                  ? l10n.analyticsOverviewUnavailable
                  : formatters.percent(withdrawal, decimalDigits: 1),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressCashRunway,
              value: cashMonths == null
                  ? l10n.analyticsFireProgressUnlimited
                  : l10n.analyticsFireProgressMonths(cashMonths),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressEta,
              value: eta == null
                  ? l10n.analyticsOverviewUnavailable
                  : l10n.analyticsOverviewFireEtaMonths(eta),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricReadout extends StatelessWidget {
  const _MetricReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.microLabelStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(value, style: context.theme.typography.sm),
        ],
      ),
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

class _AnalyticsOverviewGrid extends ConsumerWidget {
  const _AnalyticsOverviewGrid({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final header = ref.watch(dashboardHeaderMetricsProvider);
    final cashFlow = ref.watch(
      cashFlowSummaryProvider(
        const CashFlowSummaryRequest(period: CashFlowPeriod.month),
      ),
    );
    final fire = ref.watch(fireStateProvider);

    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.s12,
      crossAxisSpacing: AppSpacing.s12,
      childAspectRatio: isWide ? 1.8 : 1.2,
      children: [
        _OverviewMetricCard(
          icon: Icons.account_balance_wallet_outlined,
          label: l10n.analyticsOverviewNetWorth,
          child: snapshot.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (s) => MoneyText(
              amount: s.netWorth.amount.toDouble(),
              currencyCode: s.baseCurrency,
              compact: true,
              style: context.theme.typography.lg,
            ),
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.trending_up,
          label: l10n.analyticsOverviewMonthlyChange,
          child: header.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (metrics) {
              final formatters = ref.watch(
                appFormattersProvider(Localizations.localeOf(context)),
              );
              final pct = metrics.monthlyChangePct;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SignedMoneyText(
                    amount: metrics.monthlyChange.amount,
                    unit: metrics.baseCurrency,
                    formatters: formatters,
                    style: context.theme.typography.lg,
                  ),
                  if (pct != null)
                    Text(
                      formatters.percent(pct, decimalDigits: 1),
                      style: context.captionStyle,
                    ),
                ],
              );
            },
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.payments_outlined,
          label: l10n.analyticsOverviewCashFlow,
          child: cashFlow.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (summary) {
              final formatters = ref.watch(
                appFormattersProvider(Localizations.localeOf(context)),
              );
              return SignedMoneyText(
                amount: summary.totalInBase.amount,
                unit: summary.baseCurrency,
                formatters: formatters,
                style: context.theme.typography.lg,
              );
            },
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.flag_outlined,
          label: l10n.analyticsOverviewFireEta,
          child: fire.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (state) {
              if (!state.isConfigured) {
                return Text(
                  l10n.analyticsOverviewFireNotConfigured,
                  style: context.theme.typography.sm,
                );
              }
              final months = state.fireEtaMonths;
              return Text(
                months == null
                    ? l10n.analyticsOverviewUnavailable
                    : l10n.analyticsOverviewFireEtaMonths(months),
                style: context.theme.typography.lg,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: colors.primary),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  label,
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).analyticsOverviewUnavailable,
      style: context.theme.typography.lg,
    );
  }
}

class _OverviewUnavailable extends StatelessWidget {
  const _OverviewUnavailable();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).analyticsOverviewUnavailable,
      style: context.theme.typography.lg,
    );
  }
}

class _RiskAndBenchmarkColumn extends StatelessWidget {
  const _RiskAndBenchmarkColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskAlertPanel(),
        SizedBox(height: AppSpacing.s24),
        BenchmarkComparisonCard(),
      ],
    );
  }
}
