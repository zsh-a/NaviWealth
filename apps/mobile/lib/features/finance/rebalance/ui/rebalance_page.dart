import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';

import '../../../../core/format/formatters.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/rebalance_execution_codecs.dart';
import '../data/rebalance_providers.dart';
import '../domain/capital_allocation_engine.dart';
import '../domain/hierarchical_rebalance_engine.dart';
import '../domain/rebalance_execution.dart';
import '../domain/rebalance_models.dart';
import '../domain/universe_rebalance_engine.dart';
import 'deviation_bar.dart';

/// Rebalance page — shows target vs actual allocation, deviation bars,
/// and suggested trades.
class RebalancePage extends ConsumerWidget {
  const RebalancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(rebalancePlanProvider);
    final portfolioPlan = ref.watch(hierarchicalRebalancePlanProvider);
    final universePlan = ref.watch(universeRebalancePlanProvider);
    final active = ref.watch(activeRebalanceExecutionProvider).value;

    return AppPageScaffold(
      title: l10n.rebalanceTitle,
      childPad: false,
      child: plan == null
          ? _EmptyState(
              active: active,
              portfolioPlan: portfolioPlan,
              universePlan: universePlan,
            )
          : _RebalanceBody(
              plan: plan,
              portfolioPlan: portfolioPlan,
              universePlan: universePlan,
              active: active,
            ),
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
  const _EmptyState({
    required this.active,
    required this.portfolioPlan,
    required this.universePlan,
  });

  final RebalanceExecutionSession? active;
  final PortfolioRebalancePlan? portfolioPlan;
  final UniverseRebalancePlan? universePlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        if (universePlan != null) ...[
          _UniversePortfolioAllocation(plan: universePlan!),
          const SizedBox(height: AppSpacing.s16),
        ],
        if (portfolioPlan != null) ...[
          _PortfolioGroupSelector(plan: portfolioPlan!),
          const SizedBox(height: AppSpacing.s16),
        ],
        AppEmptyState(
          icon: FLucideIcons.scale,
          title: l10n.rebalanceEmptyTitle,
          message: l10n.rebalanceEmptyHint,
          action: active == null
              ? FButton(
                  onPress: () => context.push(FinanceRoutes.wealthPortfolio),
                  child: Text(l10n.portfolioHubTitle),
                )
              : FButton(
                  onPress: () => _openExecution(
                    context: context,
                    ref: ref,
                    active: active,
                  ),
                  child: Text(l10n.rebalanceExecutionResumeAction),
                ),
        ),
      ],
    );
  }
}

class _RebalanceBody extends StatelessWidget {
  const _RebalanceBody({
    required this.plan,
    required this.portfolioPlan,
    required this.universePlan,
    required this.active,
  });

  final RebalancePlan plan;
  final PortfolioRebalancePlan? portfolioPlan;
  final UniverseRebalancePlan? universePlan;
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
            if (universePlan != null) ...[
              _UniversePortfolioAllocation(plan: universePlan!),
              SizedBox(height: isMobile ? AppSpacing.s12 : AppSpacing.s16),
            ],
            if (portfolioPlan != null) ...[
              _PortfolioGroupSelector(plan: portfolioPlan!),
              SizedBox(height: isMobile ? AppSpacing.s12 : AppSpacing.s16),
            ],
            if (isMobile &&
                ((universePlan?.capitalPlan.transfers.isNotEmpty ?? false) ||
                    (portfolioPlan?.transfers.isNotEmpty ?? false)))
              const _MobileCapitalGate()
            else
              ResponsiveTwoColumn(
                left: _DriftOverview(plan: plan),
                right: _TradeList(
                  plan: plan,
                  active: active,
                  capitalTransfersPending:
                      (universePlan?.capitalPlan.transfers.isNotEmpty ??
                          false) ||
                      (portfolioPlan?.transfers.isNotEmpty ?? false),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UniversePortfolioAllocation extends ConsumerWidget {
  const _UniversePortfolioAllocation({required this.plan});

  final UniverseRebalancePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final selectedId = ref.watch(
      effectiveSelectedInvestmentPortfolioIdProvider,
    );
    final nameById = {
      for (final item in plan.portfolios)
        item.portfolio.id: item.portfolio.name,
    };
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.rebalanceStagePortfolioTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(l10n.rebalanceCapitalTreeHint, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => context.push(FinanceRoutes.wealthPortfolio),
              child: Text(l10n.rebalanceConfigurePlanAction),
            ),
            const SizedBox(height: AppSpacing.s8),
            FSelect<String>.rich(
              format: (id) => nameById[id] ?? id,
              control: FSelectControl<String>.lifted(
                value: selectedId,
                onChange: (value) {
                  if (value == null) return;
                  ref
                          .read(selectedInvestmentPortfolioIdProvider.notifier)
                          .state =
                      value;
                },
              ),
              children: [
                for (final item in plan.portfolios)
                  FSelectItem<String>(
                    value: item.portfolio.id,
                    title: Text(item.portfolio.name),
                    subtitle: Text(
                      l10n.rebalancePortfolioWeightPair(
                        formatters.percent(
                          item.capitalDecision.actualWeight,
                          decimalDigits: 0,
                        ),
                        formatters.percent(
                          item.capitalDecision.targetWeight,
                          decimalDigits: 0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (plan.capitalPlan.transfers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s16),
              Text(
                l10n.rebalancePortfolioTransfersTitle,
                style: context.theme.typography.body.sm,
              ),
              const SizedBox(height: AppSpacing.s8),
              for (final transfer in plan.capitalPlan.transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                  child: _CapitalTransferTile(
                    fromName:
                        nameById[transfer.fromNodeId] ?? transfer.fromNodeId,
                    toName: nameById[transfer.toNodeId] ?? transfer.toNodeId,
                    amount: formatters.currency(
                      transfer.amount.amount,
                      code: transfer.amount.currency,
                    ),
                    onResolve: () => context.push(
                      FinanceRoutes.wealthPortfolioStudioFor(
                        transfer.fromNodeId,
                        section: 'assets',
                      ),
                    ),
                  ),
                ),
            ],
            _CapitalDecisionWarnings(
              decisions: plan.capitalPlan.decisions.values
                  .where(
                    (decision) =>
                        decision.action ==
                            CapitalAllocationAction.policyBlocked ||
                        decision.action ==
                            CapitalAllocationAction.noCounterparty,
                  )
                  .map(
                    (decision) => (
                      name: decision.nodeName,
                      policyBlocked:
                          decision.action ==
                          CapitalAllocationAction.policyBlocked,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioGroupSelector extends ConsumerWidget {
  const _PortfolioGroupSelector({required this.plan});

  final PortfolioRebalancePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final selectedId = ref.watch(
      effectiveSelectedPortfolioRebalanceGroupIdProvider,
    );
    final groupNameById = {
      for (final groupPlan in plan.groups)
        groupPlan.group.id: groupPlan.group.name,
    };
    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.rebalanceStageStrategyTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            FSelect<String>.rich(
              format: (id) => groupNameById[id] ?? id,
              control: FSelectControl<String>.lifted(
                value: selectedId,
                onChange: (value) {
                  if (value == null) return;
                  ref
                          .read(
                            selectedPortfolioRebalanceGroupIdProvider.notifier,
                          )
                          .state =
                      value;
                },
              ),
              children: [
                for (final groupPlan in plan.groups)
                  FSelectItem<String>(
                    value: groupPlan.group.id,
                    title: Text(groupPlan.group.name),
                    subtitle: Text(
                      l10n.rebalancePortfolioWeightPair(
                        formatters.percent(
                          groupPlan.capitalDecision.actualWeight,
                          decimalDigits: 0,
                        ),
                        formatters.percent(
                          groupPlan.capitalDecision.targetWeight,
                          decimalDigits: 0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (plan.transfers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s16),
              Text(
                l10n.rebalanceGroupTransfersTitle,
                style: context.theme.typography.body.sm,
              ),
              const SizedBox(height: AppSpacing.s8),
              for (final transfer in plan.transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                  child: _CapitalTransferTile(
                    fromName:
                        groupNameById[transfer.fromGroupId] ??
                        transfer.fromGroupId,
                    toName:
                        groupNameById[transfer.toGroupId] ?? transfer.toGroupId,
                    amount: formatters.currency(
                      transfer.amount.amount,
                      code: transfer.amount.currency,
                    ),
                    onResolve: plan.groups.isNotEmpty
                        ? () => context.push(
                            FinanceRoutes.wealthPortfolioStudioFor(
                              plan.groups.first.group.portfolioId,
                              section: 'assets',
                            ),
                          )
                        : null,
                  ),
                ),
            ],
            _CapitalDecisionWarnings(
              decisions: plan.groups
                  .where(
                    (group) =>
                        group.capitalDecision.action ==
                            GroupCapitalAction.policyBlocked ||
                        group.capitalDecision.action ==
                            GroupCapitalAction.noCounterparty,
                  )
                  .map(
                    (group) => (
                      name: group.group.name,
                      policyBlocked:
                          group.capitalDecision.action ==
                          GroupCapitalAction.policyBlocked,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapitalTransferTile extends StatelessWidget {
  const _CapitalTransferTile({
    required this.fromName,
    required this.toName,
    required this.amount,
    this.onResolve,
  });

  final String fromName;
  final String toName;
  final String amount;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: context.theme.colors.primary.withValues(
          alpha: AppOpacity.whisper,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fromName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
                child: Icon(
                  FLucideIcons.arrowRight,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.primary,
                ),
              ),
              Expanded(
                child: Text(
                  toName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.theme.typography.body.sm,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            amount,
            textAlign: TextAlign.center,
            style: TypographyTokens.numericTitleStrong.copyWith(
              color: context.theme.colors.primary,
            ),
          ),
          if (onResolve != null) ...[
            const SizedBox(height: AppSpacing.s10),
            FButton(
              variant: FButtonVariant.primary,
              onPress: onResolve,
              prefix: const Icon(
                FLucideIcons.arrowRightLeft,
                size: AppIconSizes.sm,
              ),
              child: Text(l10n.rebalanceResolveTransferAction),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileCapitalGate extends StatelessWidget {
  const _MobileCapitalGate();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: context.theme.colors.destructive.withValues(
          alpha: AppOpacity.whisper,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FLucideIcons.circleAlert,
            size: AppIconSizes.md,
            color: context.theme.colors.destructive,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              l10n.rebalanceCapitalFirstHint,
              style: context.captionStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriftOverview extends StatelessWidget {
  const _DriftOverview({required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));

    return SoftCard.flat(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceStageAssetTitle,
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
                formatters.percent(plan.driftBeforePct, decimalDigits: 1),
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

typedef _CapitalDecisionWarning = ({String name, bool policyBlocked});

class _CapitalDecisionWarnings extends StatelessWidget {
  const _CapitalDecisionWarnings({required this.decisions});

  final List<_CapitalDecisionWarning> decisions;

  @override
  Widget build(BuildContext context) {
    if (decisions.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.rebalanceCapitalBlockedTitle,
            style: context.theme.typography.body.sm,
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final decision in decisions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FLucideIcons.circleAlert,
                    size: AppIconSizes.sm,
                    color: context.theme.colors.destructive,
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: Text(
                      decision.policyBlocked
                          ? l10n.rebalanceDecisionPolicyBlocked(decision.name)
                          : l10n.rebalanceDecisionNoCounterparty(decision.name),
                      style: context.captionStyle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TradeList extends ConsumerWidget {
  const _TradeList({
    required this.plan,
    required this.active,
    required this.capitalTransfersPending,
  });

  final RebalancePlan plan;
  final RebalanceExecutionSession? active;
  final bool capitalTransfersPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));

    if (plan.isBalanced) {
      return SoftCard.raised(
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

    return SoftCard.flat(
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
                  formatters.percent(plan.driftAfterPct, decimalDigits: 1),
                  style: context.captionLabelStyle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            if (capitalTransfersPending) ...[
              Text(
                l10n.rebalanceCapitalFirstHint,
                style: context.captionStyle.copyWith(
                  color: context.theme.colors.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            SizedBox(
              width: double.infinity,
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: capitalTransfersPending
                    ? null
                    : () => _openExecution(
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
                      capitalTransfersPending
                          ? l10n.rebalanceCapitalFirstAction
                          : active != null &&
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
