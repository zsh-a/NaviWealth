part of '../portfolio_group_sheets.dart';

class PortfolioGroupsSection extends ConsumerWidget {
  const PortfolioGroupsSection({super.key, required this.portfolioId});

  final String portfolioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(portfolioRebalanceGroupsProvider);
    return groups.whenOrLoading(
      context: context,
      onRetry: () => ref.invalidate(portfolioRebalanceGroupsProvider),
      data: (allGroups) {
        final items = allGroups
            .where((group) => group.portfolioId == portfolioId)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.portfolioGroupsSectionTitle,
                    style: context.theme.typography.body.sm,
                  ),
                ),
                if (items.isNotEmpty)
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: () =>
                        showStrategySleeveAllocationEditor(context, ref, items),
                    child: Text(l10n.capitalAllocationEditAction),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            if (items.isNotEmpty)
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      FTile(
                        prefix: const Icon(FLucideIcons.layers3),
                        title: Text(items[index].name),
                        subtitle: Text(
                          l10n.portfolioGroupWeightSummary(
                            _percentFromBps(items[index].targetWeightBps),
                            _transferPolicyLabel(
                              l10n,
                              items[index].transferPolicy,
                            ),
                          ),
                        ),
                        suffix: const Icon(
                          FLucideIcons.chevronRight,
                          size: AppIconSizes.sm,
                        ),
                        onPress: () => showEditStrategySleeve(
                          context,
                          group: items[index],
                        ),
                      ),
                      if (index != items.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.plus),
              onPress: () =>
                  showAddStrategySleeve(context, portfolioId: portfolioId),
              child: Text(l10n.portfolioGroupAddAction),
            ),
            const SizedBox(height: AppSpacing.s8),
            FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.combine),
              onPress: () =>
                  showAddStrategyRule(context, portfolioId: portfolioId),
              child: Text(l10n.portfolioOverlayAddAction),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showStrategySleeveAllocationEditor(
  BuildContext context,
  WidgetRef ref,
  List<PortfolioRebalanceGroup> groups,
) {
  final l10n = AppLocalizations.of(context);
  final groupById = {for (final group in groups) group.id: group};
  return showCapitalAllocationPlanEditor(
    context: context,
    title: l10n.portfolioStrategyAllocationEditTitle,
    subtitle: l10n.portfolioStrategyAllocationPlanSubtitle,
    weightLabel: l10n.portfolioGroupTargetWeightLabel,
    singleItemHint: l10n.portfolioGroupSingleTargetHint,
    drafts: [
      for (final group in groups)
        CapitalAllocationDraft(
          id: group.id,
          name: group.name,
          targetWeightBps: group.targetWeightBps,
          driftBandBps: group.driftBandBps,
          transferPolicy: group.transferPolicy,
        ),
    ],
    onSave: (drafts) async {
      final repository = await ref.read(
        investmentPortfolioRepositoryProvider.future,
      );
      await repository.updateStrategyPlan(
        portfolioId: groups.first.portfolioId,
        groups: [
          for (final draft in drafts)
            groupById[draft.id]!.copyWith(
              targetWeightBps: draft.targetWeightBps,
              driftBandBps: draft.driftBandBps,
              transferPolicy: draft.transferPolicy,
            ),
        ],
      );
    },
  );
}
