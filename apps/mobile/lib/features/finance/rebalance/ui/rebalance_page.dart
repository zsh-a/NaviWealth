import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/risk_appetite_preferences.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/rebalance_execution_codecs.dart';
import '../data/rebalance_providers.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
import 'deviation_bar.dart';
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
    final active = ref.watch(activeRebalanceExecutionProvider).value;

    return AppPageScaffold(
      title: l10n.rebalanceTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.slidersHorizontal),
          onPress: () => _openSettings(context, ref),
        ),
      ],
      childPad: false,
      child: plan == null
          ? _EmptyState(active: active)
          : _RebalanceBody(plan: plan, scheme: scheme, active: active),
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

Future<void> _openExecution({
  required BuildContext context,
  required WidgetRef ref,
  RebalancePlan? plan,
  RebalanceExecutionSession? active,
}) async {
  final l10n = AppLocalizations.of(context);
  if (plan == null && active != null) {
    context.go(FinanceRoutes.planRebalanceExecutionSession(active.id));
    return;
  }
  if (plan == null) return;

  try {
    final fingerprint = RebalancePlanFingerprint.compute(plan);
    if (active != null && active.planFingerprint == fingerprint) {
      context.go(FinanceRoutes.planRebalanceExecutionSession(active.id));
      return;
    }
    final gateway = await ref.read(
      rebalanceExecutionWorkspaceGatewayProvider.future,
    );
    if (!context.mounted) return;
    late final RebalanceExecutionSession session;
    if (active == null) {
      session = await gateway.createOrResume(plan);
    } else {
      final confirmed = await showConfirmDialog(
        context: context,
        title: Text(l10n.rebalanceExecutionReplaceTitle),
        body: Text(l10n.rebalanceExecutionReplaceBody),
        cancelLabel: l10n.commonCancel,
        confirmLabel: l10n.rebalanceExecutionReplaceAction,
        icon: FLucideIcons.refreshCw,
      );
      if (confirmed != true || !context.mounted) return;
      session = await gateway.replaceActive(
        expectedSessionId: active.id,
        expectedFingerprint: active.planFingerprint,
        plan: plan,
      );
    }
    ref.invalidate(activeRebalanceExecutionProvider);
    if (context.mounted) {
      context.go(FinanceRoutes.planRebalanceExecutionSession(session.id));
    }
  } catch (error, stackTrace) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'open rebalance execution',
        ),
      );
    }
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.active});

  final RebalanceExecutionSession? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.scale,
      title: l10n.rebalanceEmptyTitle,
      message: l10n.rebalanceEmptyHint,
      action: active == null
          ? null
          : FButton(
              onPress: () =>
                  _openExecution(context: context, ref: ref, active: active),
              child: Text(l10n.rebalanceExecutionResumeAction),
            ),
    );
  }
}

class _RebalanceBody extends StatelessWidget {
  const _RebalanceBody({
    required this.plan,
    required this.scheme,
    required this.active,
  });

  final RebalancePlan plan;
  final AllocationSchemePreset scheme;
  final RebalanceExecutionSession? active;

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
              right: _TradeList(plan: plan, active: active),
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
            Text(
              l10n.rebalanceSchemeTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final preset in AllocationSchemePreset.values)
                  if (preset != AllocationSchemePreset.custom)
                    FButton(
                      variant: (current == preset)
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      onPress: () => _selectPreset(context, ref, preset),
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
    BuildContext context,
    WidgetRef ref,
    AllocationSchemePreset preset,
  ) async {
    if (current == preset) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.settingsRiskAppetiteConfirmTitle),
      body: Text(
        l10n.settingsRiskAppetiteConfirmBody(_schemeLabel(l10n, preset)),
      ),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.settingsRiskAppetiteConfirmAction,
      icon: FLucideIcons.slidersHorizontal,
    );
    if (confirmed != true || !context.mounted) return;
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
                    style: context.theme.typography.body.sm,
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
                      style: context.microLabelStyle.copyWith(
                        color: context.theme.colors.primary,
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
              style: context.captionStyle,
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

class _TradeList extends ConsumerWidget {
  const _TradeList({required this.plan, required this.active});

  final RebalancePlan plan;
  final RebalanceExecutionSession? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              Text(
                l10n.rebalanceBalanced,
                style: context.theme.typography.body.sm,
              ),
              if (active != null) ...[
                const SizedBox(height: AppSpacing.s12),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => _openExecution(
                    context: context,
                    ref: ref,
                    active: active,
                  ),
                  child: Text(l10n.rebalanceExecutionResumeAction),
                ),
              ],
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
            Text(
              l10n.rebalanceTradeTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final trade in plan.trades) _TradeRow(trade: trade),
            const FDivider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedFees,
                    style: context.captionStyle,
                  ),
                ),
                AnimatedMoneyText(
                  amount: plan.estimatedFees.amount.toDouble(),
                  currencyCode: plan.estimatedFees.currency,
                  compact: true,
                  style: context.theme.typography.body.xs,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedTaxes,
                    style: context.captionStyle,
                  ),
                ),
                AnimatedMoneyText(
                  amount: plan.estimatedTaxes.amount.toDouble(),
                  currencyCode: plan.estimatedTaxes.currency,
                  compact: true,
                  style: context.theme.typography.body.xs,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceDriftAfter,
                    style: context.captionStyle,
                  ),
                ),
                Text(
                  '${(plan.driftAfterPct * 100).toStringAsFixed(1)}%',
                  style: context.captionLabelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            SizedBox(
              width: double.infinity,
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: () => _openExecution(
                  context: context,
                  ref: ref,
                  plan: plan,
                  active: active,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FLucideIcons.listChecks, size: AppIconSizes.h18),
                    const SizedBox(width: AppSpacing.s6),
                    Text(
                      active != null &&
                              active!.planFingerprint ==
                                  RebalancePlanFingerprint.compute(plan)
                          ? l10n.rebalanceExecutionResumeAction
                          : l10n.rebalanceExecuteAction,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.theme.colors.foreground.withValues(
                alpha: AppOpacity.whisper,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: AppIconSizes.h18,
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$directionLabel $label',
                  style: context.theme.typography.body.sm,
                ),
                if (trade.isAssetTarget)
                  Text(
                    AssetCategoryVisuals.label(l10n, trade.category),
                    style: context.captionStyle,
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
          style: context.theme.typography.body.sm,
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
          style: context.theme.typography.body.sm,
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
