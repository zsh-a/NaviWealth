import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/format/providers.dart';
import '../../design_system/design_system.dart';
import '../../features/cashflow/data/cash_flow_providers.dart';
import '../../features/cashflow/domain/cash_flow_aggregator.dart';
import '../../features/fire/data/fire_providers.dart';
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
