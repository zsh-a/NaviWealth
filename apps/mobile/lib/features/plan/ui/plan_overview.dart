import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../analytics/data/providers.dart';
import '../../analytics/domain/concentration_risk.dart';
import '../../fire/data/fire_providers.dart';
import '../../fire/domain/fire_projection.dart';
import '../../rebalance/data/rebalance_providers.dart';

class PlanOverview extends ConsumerWidget {
  const PlanOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final fireView = ref.watch(fireDashboardViewProvider);
    final riskAlerts = ref.watch(concentrationAlertsProvider);
    final rebalancePlan = ref.watch(rebalancePlanProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !Breakpoints.isMobile(constraints.maxWidth);
        final padding = isWide
            ? const EdgeInsets.all(24)
            : const EdgeInsets.all(16);

        final cards = <Widget>[
          _PlanCard(
            icon: Icons.flag_outlined,
            title: l10n.planFireTitle,
            subtitle: l10n.planFireSubtitle,
            summary: fireView.when(
              loading: () => const [_SummarySkeleton()],
              error: (_, _) => [_SummaryChip(label: l10n.planSummaryLoadError)],
              data: (view) => _fireSummary(l10n, formatters, view),
            ),
            onTap: () => context.push(AppRoutes.planFire),
          ),
          _PlanCard(
            icon: Icons.pie_chart_outline,
            title: l10n.planAnalyticsTitle,
            subtitle: l10n.planAnalyticsSubtitle,
            summary: riskAlerts.when(
              loading: () => const [_SummarySkeleton()],
              error: (_, _) => [_SummaryChip(label: l10n.planSummaryLoadError)],
              data: (alerts) => _riskSummary(l10n, alerts),
            ),
            onTap: () => context.push(AppRoutes.planAnalytics),
          ),
          _PlanCard(
            icon: Icons.balance_outlined,
            title: l10n.planRebalanceTitle,
            subtitle: l10n.planRebalanceSubtitle,
            summary: rebalancePlan == null
                ? [_SummaryChip(label: l10n.planSummaryNoPortfolio)]
                : [
                    _SummaryChip(
                      label: rebalancePlan.isBalanced
                          ? l10n.planSummaryBalanced
                          : l10n.planSummaryDrift(
                              formatters.percent(
                                rebalancePlan.driftBeforePct,
                                decimalDigits: 1,
                              ),
                            ),
                    ),
                    if (!rebalancePlan.isBalanced)
                      _SummaryChip(
                        label: l10n.planSummaryTrades(
                          rebalancePlan.trades.length,
                        ),
                      ),
                  ],
            onTap: () => context.push(AppRoutes.planRebalance),
          ),
        ];

        if (isWide) {
          return ListView(
            padding: padding,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 16),
              cards[2],
            ],
          );
        }

        return ListView(
          padding: padding.copyWith(
            bottom: padding.bottom + 64 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i < cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _fireSummary(
    AppLocalizations l10n,
    AppFormatters formatters,
    FireDashboardView view,
  ) {
    final progress = view.progressRatio;
    if (progress == null) {
      return [_SummaryChip(label: l10n.planSummaryConfigureGoal)];
    }
    final scenario = _baselineScenario(view);
    return [
      _SummaryChip(
        label: l10n.planSummaryProgress(
          formatters.percent(progress, decimalDigits: 0),
        ),
      ),
      _SummaryChip(label: l10n.planSummaryEta(_formatMonths(l10n, scenario))),
    ];
  }

  List<Widget> _riskSummary(
    AppLocalizations l10n,
    List<ConcentrationAlert> alerts,
  ) {
    if (alerts.isEmpty) {
      return [_SummaryChip(label: l10n.planSummaryNoRiskAlerts)];
    }
    final critical = alerts
        .where((a) => a.severity == RiskSeverity.critical)
        .length;
    return [
      _SummaryChip(label: l10n.planSummaryRiskAlerts(alerts.length)),
      if (critical > 0)
        _SummaryChip(label: l10n.planSummaryCriticalAlerts(critical)),
    ];
  }

  FireScenario _baselineScenario(FireDashboardView view) {
    return view.scenarios.firstWhere(
      (s) => s.tier == FireScenarioTier.live,
      orElse: () => view.scenarios.firstWhere(
        (s) => s.tier == FireScenarioTier.neutral,
        orElse: () => view.scenarios.first,
      ),
    );
  }

  String _formatMonths(AppLocalizations l10n, FireScenario scenario) {
    final months = scenario.monthsToTarget;
    if (months == null) return l10n.fireCountdownUnreachableShort;
    if (months == 0) return l10n.fireScenarioReachedNow;
    final years = months ~/ 12;
    final mm = months % 12;
    if (years == 0) return l10n.fireCountdownMonthsOnly(mm);
    if (mm == 0) return l10n.fireCountdownYearsOnly(years);
    return l10n.fireCountdownYearsMonths(years, mm);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FCard.raw(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: context.theme.colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.theme.typography.md),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: context.theme.typography.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: summary),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: context.theme.colors.mutedForeground,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: context.theme.typography.xs2.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(width: 80, height: 20, radius: 8);
  }
}
