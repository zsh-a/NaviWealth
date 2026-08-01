part of 'portfolio_hub_page.dart';

class _StudioStructure extends StatelessWidget {
  const _StudioStructure({
    required this.portfolio,
    required this.sleeves,
    required this.tree,
  });

  final InvestmentPortfolio portfolio;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioStudioStructureTitle,
          subtitle: l10n.portfolioStudioStructureHint,
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () =>
                showAddStrategySleeve(context, portfolioId: portfolio.id),
            prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
            child: Text(l10n.portfolioGroupAddAction),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (sleeves.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.layers3,
            title: l10n.portfolioGroupNoTemplates,
            action: FButton(
              onPress: () =>
                  showAddStrategySleeve(context, portfolioId: portfolio.id),
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.portfolioGroupAddAction),
            ),
          )
        else
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < sleeves.length; index++) ...[
                  _SleeveTile(node: sleeves[index], tree: tree),
                  if (index != sleeves.length - 1)
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
}

class _SleeveTile extends ConsumerWidget {
  const _SleeveTile({required this.node, required this.tree});

  final AllocationNode node;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups =
        ref.watch(portfolioRebalanceGroupsProvider).value ?? const [];
    final group = groups
        .where((candidate) => candidate.id == node.referenceId)
        .firstOrNull;
    final assets = tree.childrenOf(node.id);
    return FTile(
      prefix: const Icon(FLucideIcons.layers3),
      title: Text(node.name),
      subtitle: Text(
        l10n.portfolioStudioSleeveSummary(
          _studioPercentFromBps(node.targetWeightBps),
          assets.length,
          _studioTransferPolicyLabel(l10n, node.transferPolicy),
        ),
      ),
      suffix: const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
      onPress: group == null
          ? null
          : () => showEditStrategySleeve(context, group: group),
    );
  }
}

class _StudioRules extends ConsumerWidget {
  const _StudioRules({
    required this.portfolio,
    required this.sleeves,
    required this.tree,
  });

  final InvestmentPortfolio portfolio;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final templates =
        ref.watch(portfolioStrategyTemplatesProvider).value ??
        kBuiltInPortfolioStrategyTemplates;
    final languageCode = Localizations.localeOf(context).languageCode;
    final rules = [
      for (final sleeve in sleeves)
        for (final attachment in tree.attachmentsFor(sleeve.id))
          if (!attachment.isPrimary) (sleeve: sleeve, attachment: attachment),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioStudioRulesTitle,
          subtitle: l10n.portfolioStudioRulesHint,
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () =>
                showAddStrategyRule(context, portfolioId: portfolio.id),
            prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
            child: Text(l10n.portfolioOverlayAddAction),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        if (rules.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.sparkles,
            title: l10n.portfolioStudioNoRules,
            action: FButton(
              onPress: () =>
                  showAddStrategyRule(context, portfolioId: portfolio.id),
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.portfolioOverlayAddAction),
            ),
          )
        else
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < rules.length; index++) ...[
                  FTile(
                    prefix: const Icon(FLucideIcons.sparkles),
                    title: Text(
                      strategyTemplateForKind(
                            templates,
                            rules[index].attachment.kind,
                          )?.displayName(languageCode) ??
                          rules[index].attachment.kind.wire,
                    ),
                    subtitle: Text(rules[index].sleeve.name),
                  ),
                  if (index != rules.length - 1)
                    const AppGroupedDivider(
                      indent: AppSpacing.s12,
                      endIndent: AppSpacing.s12,
                    ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s12),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => showPortfolioStrategyLibrarySheet(context),
          prefix: const Icon(FLucideIcons.library),
          child: Text(l10n.portfolioStrategyLibraryTitle),
        ),
      ],
    );
  }
}
