import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/ui/asset_category_visuals.dart';
import '../../investment/presentation/trade_entry_form_page.dart';
import '../../settings/data/risk_appetite_preferences.dart';
import '../application/rebalance_trade_entry_prefills.dart';
import '../data/rebalance_providers.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_models.dart';
import 'deviation_bar.dart';
import 'rebalance_execution_sheet.dart';
import 'target_allocation_editor_sheet.dart';

/// Rebalance page — shows target vs actual allocation, deviation bars,
/// and suggested trades.
class RebalancePage extends ConsumerWidget {
  const RebalancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(rebalancePlanProvider);
    final scheme = ref.watch(selectedSchemeProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.rebalanceTitle),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.slidersHorizontal),
            onPress: () => _openSettings(context, ref),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: plan == null
            ? _EmptyState()
            : _RebalanceBody(plan: plan, scheme: scheme),
      ),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context).rebalanceSettingsTitle,
      builder: (_) => const _SettingsSheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.scale,
      title: l10n.rebalanceEmptyTitle,
      message: l10n.rebalanceEmptyHint,
    );
  }
}

class _RebalanceBody extends StatelessWidget {
  const _RebalanceBody({required this.plan, required this.scheme});

  final RebalancePlan plan;
  final AllocationSchemePreset scheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Breakpoints.isMobile(constraints.maxWidth);
        final padding = isMobile
            ? const EdgeInsets.all(AppSpacing.s16)
            : const EdgeInsets.all(AppSpacing.s24);
        return ListView(
          padding: padding,
          children: [
            _SchemeSelector(current: scheme),
            SizedBox(height: isMobile ? AppSpacing.s12 : AppSpacing.s16),
            ResponsiveTwoColumn(
              left: _DriftOverview(plan: plan),
              right: _TradeList(plan: plan),
            ),
          ],
        );
      },
    );
  }
}

class _SchemeSelector extends ConsumerWidget {
  const _SchemeSelector({required this.current});

  final AllocationSchemePreset current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rebalanceSchemeTitle, style: context.theme.typography.sm),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in AllocationSchemePreset.values)
                  if (preset != AllocationSchemePreset.custom)
                    FButton(
                      variant: (current == preset)
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      onPress: () => _selectPreset(ref, preset),
                      child: Text(_schemeLabel(l10n, preset)),
                    ),
                FButton(
                  variant: (current == AllocationSchemePreset.custom)
                      ? FButtonVariant.primary
                      : FButtonVariant.outline,
                  onPress: () =>
                      showTargetAllocationEditorSheet(context: context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.pencil, size: AppIconSizes.sm),
                      const SizedBox(width: AppSpacing.s6),
                      Text(l10n.targetAllocationEditorEditAction),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _schemeLabel(AppLocalizations l10n, AllocationSchemePreset preset) {
    switch (preset) {
      case AllocationSchemePreset.conservative:
        return l10n.rebalanceSchemeConservative;
      case AllocationSchemePreset.balanced:
        return l10n.rebalanceSchemeBalanced;
      case AllocationSchemePreset.aggressive:
        return l10n.rebalanceSchemeAggressive;
      case AllocationSchemePreset.custom:
        return l10n.rebalanceSchemeCustom;
    }
  }

  Future<void> _selectPreset(
    WidgetRef ref,
    AllocationSchemePreset preset,
  ) async {
    // Risk appetite is the single source of truth; the scheme provider
    // simply reflects it. We write the appetite, then refresh the
    // target weights to the preset's defaults so the user sees the new
    // bars immediately.
    await ref
        .read(riskAppetiteProvider.notifier)
        .set(appetiteForScheme(preset));
    await ref
        .read(targetAllocationProvider.notifier)
        .update(allocationScheme(preset));
  }
}

class _DriftOverview extends StatelessWidget {
  const _DriftOverview({required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceDriftTitle,
                    style: context.theme.typography.sm,
                  ),
                ),
                if (plan.isBalanced)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: context.theme.colors.primary.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      l10n.rebalanceBalanced,
                      style: context.theme.typography.xs2.copyWith(
                        color: context.theme.colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.rebalanceOverallDrift(
                '${(plan.driftBeforePct * 100).toStringAsFixed(1)}%',
              ),
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final drift in plan.drifts)
              DeviationBar(
                label: _targetLabel(l10n, drift),
                actualWeight: drift.actualWeight,
                targetWeight: drift.targetWeight,
                deviation: drift.deviation,
                severity: drift.severity,
              ),
          ],
        ),
      ),
    );
  }
}

class _TradeList extends StatelessWidget {
  const _TradeList({required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (plan.isBalanced) {
      return SoftCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            children: [
              Icon(
                FLucideIcons.circleCheck,
                size: AppIconSizes.xxl,
                color: context.theme.colors.primary,
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(l10n.rebalanceBalanced, style: context.theme.typography.sm),
            ],
          ),
        ),
      );
    }

    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rebalanceTradeTitle, style: context.theme.typography.sm),
            const SizedBox(height: AppSpacing.s8),
            for (final trade in plan.trades) _TradeRow(trade: trade),
            const FDivider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedFees,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
                AnimatedMoneyText(
                  amount: plan.estimatedFees.amount.toDouble(),
                  currencyCode: plan.estimatedFees.currency,
                  compact: true,
                  style: context.theme.typography.xs,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedTaxes,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
                AnimatedMoneyText(
                  amount: plan.estimatedTaxes.amount.toDouble(),
                  currencyCode: plan.estimatedTaxes.currency,
                  compact: true,
                  style: context.theme.typography.xs,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceDriftAfter,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
                Text(
                  '${(plan.driftAfterPct * 100).toStringAsFixed(1)}%',
                  style: context.theme.typography.xs.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            SizedBox(
              width: double.infinity,
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: () => _startExecution(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FLucideIcons.listChecks, size: AppIconSizes.h18),
                    const SizedBox(width: AppSpacing.s6),
                    Text(l10n.rebalanceExecuteAction),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startExecution(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showRebalanceExecutionSheet(
      context: context,
      plan: plan,
    );
    if (confirmed != true || !context.mounted) return;

    final drafts = buildRebalanceTradeEntryPrefills(
      plan: plan,
      tradeDate: DateTime.now(),
      noteBuilder: (trade) => l10n.rebalanceExecutionDraftNote(
        trade.isBuy ? l10n.rebalanceBuy : l10n.rebalanceSell,
        _tradeTargetLabel(l10n, trade),
        trade.amount.amount.toString(),
        trade.amount.currency,
      ),
    );
    for (final draft in drafts) {
      final recorded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => TradeEntryFormPage(prefill: draft)),
      );
      if (!context.mounted || recorded != true) return;
    }
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final SuggestedTrade trade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isBuy = trade.isBuy;
    final directionLabel = isBuy ? l10n.rebalanceBuy : l10n.rebalanceSell;
    final directionColor = isBuy
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    final icon = AssetCategoryVisuals.icon(trade.category);
    final label = _tradeTargetLabel(l10n, trade);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: directionColor,
              borderRadius: BorderRadius.circular(AppRadius.xxs),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Icon(
            icon,
            size: AppIconSizes.h18,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$directionLabel $label',
                  style: context.theme.typography.sm,
                ),
                if (trade.isAssetTarget)
                  Text(
                    AssetCategoryVisuals.label(l10n, trade.category),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          AnimatedMoneyText(
            amount: trade.amount.amount.toDouble(),
            currencyCode: trade.amount.currency,
            compact: true,
            showSign: false,
          ),
        ],
      ),
    );
  }
}

String _targetLabel(AppLocalizations l10n, Drift drift) =>
    drift.targetLabel ?? AssetCategoryVisuals.label(l10n, drift.category);

String _tradeTargetLabel(AppLocalizations l10n, SuggestedTrade trade) =>
    trade.targetLabel ?? AssetCategoryVisuals.label(l10n, trade.category);

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final warning = ref.watch(warningThresholdProvider);
    final critical = ref.watch(criticalThresholdProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.rebalanceWarningThreshold,
          style: context.theme.typography.sm,
        ),
        FSlider(
          control: FSliderControl.managedContinuous(
            initial: FSliderValue(max: (warning - 0.01) / 0.19),
            onChange: (v) => ref
                .read(warningThresholdProvider.notifier)
                .set(0.01 + v.max * 0.19),
          ),
          tooltipBuilder: (_, v) =>
              Text('${((0.01 + v * 0.19) * 100).toStringAsFixed(0)}%'),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          l10n.rebalanceCriticalThreshold,
          style: context.theme.typography.sm,
        ),
        FSlider(
          control: FSliderControl.managedContinuous(
            initial: FSliderValue(max: (critical - 0.05) / 0.25),
            onChange: (v) => ref
                .read(criticalThresholdProvider.notifier)
                .set(0.05 + v.max * 0.25),
          ),
          tooltipBuilder: (_, v) =>
              Text('${((0.05 + v * 0.25) * 100).toStringAsFixed(0)}%'),
        ),
      ],
    );
  }
}
