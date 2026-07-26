import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../composition/income_strategy_modules.dart';
import '../composition/income_strategy_presentation.dart';
import '../data/providers.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';
import 'income_strategy_plan_sheet.dart';

enum _IncomeStrategyTab { overview, underlyings, activity }

class IncomeStrategyPage extends ConsumerStatefulWidget {
  const IncomeStrategyPage({super.key});

  @override
  ConsumerState<IncomeStrategyPage> createState() => _IncomeStrategyPageState();
}

class _IncomeStrategyPageState extends ConsumerState<IncomeStrategyPage> {
  _IncomeStrategyTab _tab = _IncomeStrategyTab.overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(portfolioIncomeStrategyProvider);
    final plans = ref.watch(incomeStrategyPlansProvider);
    final modules = ref.watch(incomeStrategyModulesProvider);
    return AppPageScaffold(
      title: l10n.incomeStrategyTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.incomeStrategyPlanAdd,
          icon: const Icon(FLucideIcons.plus),
          onPress: () => showIncomeStrategyPlanSheet(context),
        ),
      ],
      childPad: false,
      child: snapshot.whenOrLoading(
        context: context,
        error: (error, stackTrace) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(portfolioIncomeStrategyProvider),
        ),
        data: (data) {
          final planByAsset = {
            for (final plan in plans.value ?? const <IncomeStrategyPlan>[])
              plan.assetId: plan,
          };
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s12,
                  AppSpacing.s16,
                  AppSpacing.s8,
                ),
                child: SegmentedRow<_IncomeStrategyTab>(
                  options: _IncomeStrategyTab.values,
                  value: _tab,
                  labelOf: (tab) => switch (tab) {
                    _IncomeStrategyTab.overview =>
                      l10n.incomeStrategyTabOverview,
                    _IncomeStrategyTab.underlyings =>
                      l10n.incomeStrategyTabUnderlyings,
                    _IncomeStrategyTab.activity =>
                      l10n.incomeStrategyTabActivity,
                  },
                  iconOf: (tab) => switch (tab) {
                    _IncomeStrategyTab.overview => FLucideIcons.gauge,
                    _IncomeStrategyTab.underlyings => FLucideIcons.layers3,
                    _IncomeStrategyTab.activity => FLucideIcons.listTree,
                  },
                  onChanged: (value) => setState(() => _tab = value),
                ),
              ),
              Expanded(
                child: switch (_tab) {
                  _IncomeStrategyTab.overview => _Overview(
                    snapshot: data,
                    planByAsset: planByAsset,
                    modules: modules,
                  ),
                  _IncomeStrategyTab.underlyings => _Underlyings(
                    snapshot: data,
                    planByAsset: planByAsset,
                    modules: modules,
                  ),
                  _IncomeStrategyTab.activity => _Activity(
                    snapshot: data,
                    modules: modules,
                  ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.snapshot,
    required this.planByAsset,
    required this.modules,
  });

  final PortfolioIncomeStrategySnapshot snapshot;
  final Map<String, IncomeStrategyPlan> planByAsset;
  final List<IncomeStrategyModule> modules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.underlyings.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: FLucideIcons.layers3,
          title: l10n.incomeStrategyEmptyTitle,
          message: l10n.incomeStrategyEmptyBody,
          action: FButton(
            onPress: () => showIncomeStrategyPlanSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 168),
              child: Text(
                l10n.incomeStrategyPlanAdd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    final risks = snapshot.underlyings
        .expand((underlying) => underlying.risks)
        .where((risk) => risk.severity != IncomeStrategyRiskSeverity.info)
        .take(4)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        SoftCard.raised(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Wrap(
            spacing: AppSpacing.s20,
            runSpacing: AppSpacing.s16,
            children: [
              _Metric(
                label: l10n.incomeStrategyRealizedResult,
                value: _metricMoney(l10n, snapshot.realizedResult),
              ),
              _Metric(
                label: l10n.incomeStrategyProjectedCash,
                value: _metricMoney(l10n, snapshot.projectedCash),
              ),
              _Metric(
                label: l10n.incomeStrategyCapitalAtRisk,
                value: _metricMoney(l10n, snapshot.capitalAtRisk),
              ),
              _Metric(
                label: l10n.incomeStrategyRiskCount,
                value: snapshot.activeRiskCount.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _WorkspaceActions(),
        if (risks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s20),
          Text(l10n.incomeStrategyRisksTitle, style: context.mutedLabelStyle),
          const SizedBox(height: AppSpacing.s8),
          for (final risk in risks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: _RiskRow(risk: risk, modules: modules),
            ),
        ],
        const SizedBox(height: AppSpacing.s20),
        Text(
          l10n.incomeStrategyUnderlyingsTitle,
          style: context.mutedLabelStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final underlying in snapshot.underlyings.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: _StrategyTrack(
              underlying: underlying,
              plan: planByAsset[underlying.asset.assetId],
              modules: modules,
            ),
          ),
      ],
    );
  }
}

class _Underlyings extends StatelessWidget {
  const _Underlyings({
    required this.snapshot,
    required this.planByAsset,
    required this.modules,
  });

  final PortfolioIncomeStrategySnapshot snapshot;
  final Map<String, IncomeStrategyPlan> planByAsset;
  final List<IncomeStrategyModule> modules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.underlyings.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: FLucideIcons.layers3,
          title: l10n.incomeStrategyEmptyTitle,
          action: FButton(
            onPress: () => showIncomeStrategyPlanSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 168),
              child: Text(
                l10n.incomeStrategyPlanAdd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      itemCount: snapshot.underlyings.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
      itemBuilder: (context, index) {
        final underlying = snapshot.underlyings[index];
        return _StrategyTrack(
          underlying: underlying,
          plan: planByAsset[underlying.asset.assetId],
          modules: modules,
        );
      },
    );
  }
}

class _StrategyTrack extends StatelessWidget {
  const _StrategyTrack({
    required this.underlying,
    required this.plan,
    required this.modules,
  });

  final UnderlyingIncomeStrategySnapshot underlying;
  final IncomeStrategyPlan? plan;
  final List<IncomeStrategyModule> modules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeRisks = underlying.risks
        .where((risk) => risk.severity != IncomeStrategyRiskSeverity.info)
        .length;
    return SoftCard.raised(
      onPress: () => showIncomeStrategyPlanSheet(
        context,
        asset: underlying.asset,
        existing: plan,
      ),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(underlying.asset.symbol, style: context.labelStyle),
                    Text(
                      underlying.asset.displayLabel,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              if (activeRisks > 0)
                AppBadge(
                  label: l10n.incomeStrategyRiskSummary(activeRisks),
                  tone: AppBadgeTone.warning,
                )
              else
                AppBadge(
                  label: l10n.incomeStrategyPlanAligned,
                  tone: AppBadgeTone.neutral,
                ),
              const SizedBox(width: AppSpacing.s8),
              const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 640
                  ? (constraints.maxWidth - AppSpacing.s16) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final module in modules)
                    SizedBox(
                      width: width,
                      child: _SleeveLane(
                        module: module,
                        enabled: underlying.enabledSleeves.contains(module.id),
                        snapshot: underlying.sleeves[module.id],
                        baseCurrency: underlying.baseCurrency,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SleeveLane extends StatelessWidget {
  const _SleeveLane({
    required this.module,
    required this.enabled,
    required this.snapshot,
    required this.baseCurrency,
  });

  final IncomeStrategyModule module;
  final bool enabled;
  final IncomeStrategySleeveSnapshot? snapshot;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = snapshot;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.foreground.withValues(
          alpha: enabled ? AppOpacity.whisper : AppOpacity.hoverTint,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(module.presentation.icon, size: AppIconSizes.sm),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    module.presentation.label(l10n),
                    style: context.labelStyle,
                  ),
                ),
                Text(
                  enabled
                      ? l10n.incomeStrategyEnabled
                      : l10n.incomeStrategyDisabled,
                  style: context.captionStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              value == null
                  ? l10n.incomeStrategyNoPosition
                  : module.presentation.statusLabel(l10n, value.status),
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              value == null ? '—' : _metricMoney(l10n, value.realizedResult),
              style: context.labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.snapshot, required this.modules});

  final PortfolioIncomeStrategySnapshot snapshot;
  final List<IncomeStrategyModule> modules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activity = snapshot.activity;
    if (activity.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: FLucideIcons.listTree,
          title: l10n.incomeStrategyActivityEmpty,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      itemCount: activity.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
      itemBuilder: (context, index) {
        final flow = activity[index];
        return SoftCard.flat(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            children: [
              Icon(
                _cashFlowPresentation(modules, flow.kind)?.icon ??
                    FLucideIcons.circleDollarSign,
                size: AppIconSizes.md,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _cashFlowPresentation(modules, flow.kind)?.label(l10n) ??
                          flow.kind.wire,
                      style: context.labelStyle,
                    ),
                    Text(
                      '${flow.assetId} · '
                      '${MaterialLocalizations.of(context).formatShortDate(flow.date.toLocal())}',
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              MoneyText(
                amount: flow.amount.amount.toDouble(),
                currencyCode: flow.amount.currency,
                showSign: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => context.push(FinanceRoutes.cashflowDividends),
          child: Text(l10n.incomeStrategyOpenDividendCenter),
        ),
        if (!kIsWeb)
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => context.push(FinanceRoutes.planIncomeOptions),
            child: Text(l10n.incomeStrategyOpenOptionsPlanner),
          ),
      ],
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.risk, required this.modules});

  final IncomeStrategyRisk risk;
  final List<IncomeStrategyModule> modules;

  @override
  Widget build(BuildContext context) => SoftCard.flat(
    padding: const EdgeInsets.all(AppSpacing.s12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(FLucideIcons.triangleAlert, size: AppIconSizes.sm),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            _riskLabel(AppLocalizations.of(context), modules, risk.code),
            style: context.bodyCaptionStyle,
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 132),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: AppSpacing.s2),
        Text(value, style: context.titleLabelStyle),
      ],
    ),
  );
}

String _metricMoney(AppLocalizations l10n, IncomeStrategyMoneyMetric metric) {
  final value = '${metric.value.currency} ${metric.value.amount}';
  return metric.quality == IncomeStrategyMetricQuality.complete
      ? value
      : '$value · ${l10n.incomeStrategyMetricPartial}';
}

IncomeStrategyCashFlowPresentation? _cashFlowPresentation(
  Iterable<IncomeStrategyModule> modules,
  IncomeStrategyCashFlowKind kind,
) {
  for (final module in modules) {
    for (final presentation in module.presentation.cashFlows) {
      if (presentation.kind == kind) return presentation;
    }
  }
  return null;
}

String _riskLabel(
  AppLocalizations l10n,
  Iterable<IncomeStrategyModule> modules,
  IncomeStrategyRiskCode code,
) {
  for (final module in modules) {
    for (final presentation in module.presentation.risks) {
      if (presentation.code == code) return presentation.label(l10n);
    }
  }
  return switch (code.wire) {
    'unplanned_sleeve' => l10n.incomeStrategyRiskUnplanned,
    'capital_budget_exceeded' => l10n.incomeStrategyRiskCapitalBudget,
    'concentration_exceeded' => l10n.incomeStrategyRiskConcentration,
    'missing_fx_rate' => l10n.incomeStrategyRiskMissingFx,
    'stale_valuation' => l10n.incomeStrategyRiskStaleValuation,
    'income_target_at_risk' => l10n.incomeStrategyRiskIncomeTarget,
    'expiration_near' => l10n.incomeStrategyRiskExpiration,
    _ => code.wire,
  };
}
