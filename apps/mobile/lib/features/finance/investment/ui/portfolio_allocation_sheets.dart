import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/investment_portfolio_providers.dart';
import '../domain/models/investment_portfolio.dart';
import 'capital_allocation_plan_editor.dart';

class PortfolioAllocationPlanSection extends ConsumerWidget {
  const PortfolioAllocationPlanSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final targets = ref.watch(activeUniversePortfolioTargetsProvider);
    return switch ((portfolios, targets)) {
      (
        AsyncData(value: final portfolioItems),
        AsyncData(value: final targetItems),
      ) =>
        _PortfolioAllocationPlanContent(
          portfolios: portfolioItems,
          targets: targetItems,
        ),
      (AsyncError(:final error, :final stackTrace), _) ||
      (_, AsyncError(:final error, :final stackTrace)) => AppEmptyState.error(
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load portfolio allocation plan',
        ),
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            ref.invalidate(investmentPortfoliosProvider);
            ref.invalidate(portfolioAllocationTargetsProvider);
          },
          child: Text(l10n.commonRetry),
        ),
      ),
      _ => const Center(child: FCircularProgress()),
    };
  }
}

class _PortfolioAllocationPlanContent extends ConsumerWidget {
  const _PortfolioAllocationPlanContent({
    required this.portfolios,
    required this.targets,
  });

  final List<InvestmentPortfolio> portfolios;
  final List<PortfolioAllocationTarget> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portfolioById = {
      for (final portfolio in portfolios) portfolio.id: portfolio,
    };
    final visibleTargets = [
      for (final target in targets)
        if (portfolioById.containsKey(target.portfolioId)) target,
    ];
    if (visibleTargets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.portfolioAllocationSectionTitle,
                style: context.theme.typography.body.sm,
              ),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => _edit(
                context,
                ref,
                targets: visibleTargets,
                portfolioById: portfolioById,
              ),
              child: Text(l10n.capitalAllocationEditAction),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < visibleTargets.length; index++) ...[
                FTile(
                  prefix: const Icon(FLucideIcons.layers),
                  title: Text(
                    portfolioById[visibleTargets[index].portfolioId]!.name,
                  ),
                  subtitle: Text(
                    l10n.portfolioAllocationWeightSummary(
                      _percentFromBps(visibleTargets[index].targetWeightBps),
                    ),
                  ),
                  suffix: Text(
                    '${_percentFromBps(visibleTargets[index].targetWeightBps)}%',
                    style: context.captionLabelStyle,
                  ),
                  onPress: () => _edit(
                    context,
                    ref,
                    targets: visibleTargets,
                    portfolioById: portfolioById,
                  ),
                ),
                if (index != visibleTargets.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required List<PortfolioAllocationTarget> targets,
    required Map<String, InvestmentPortfolio> portfolioById,
  }) {
    final l10n = AppLocalizations.of(context);
    final targetById = {for (final target in targets) target.id: target};
    return showCapitalAllocationPlanEditor(
      context: context,
      title: l10n.portfolioAllocationEditTitle,
      subtitle: l10n.portfolioAllocationPlanSubtitle,
      weightLabel: l10n.portfolioAllocationTargetWeightLabel,
      singleItemHint: l10n.portfolioAllocationSingleTargetHint,
      drafts: [
        for (final target in targets)
          CapitalAllocationDraft(
            id: target.id,
            name: portfolioById[target.portfolioId]!.name,
            targetWeightBps: target.targetWeightBps,
            driftBandBps: target.driftBandBps,
            transferPolicy: target.transferPolicy,
          ),
      ],
      onSave: (drafts) async {
        final repository = await ref.read(
          investmentPortfolioRepositoryProvider.future,
        );
        await repository.updatePortfolioPlan(
          universeId: targets.first.universeId,
          targets: [
            for (final draft in drafts)
              targetById[draft.id]!.copyWith(
                targetWeightBps: draft.targetWeightBps,
                driftBandBps: draft.driftBandBps,
                transferPolicy: draft.transferPolicy,
              ),
          ],
        );
      },
    );
  }
}

String _percentFromBps(int value) {
  final percent = value / 100;
  return percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(2);
}
