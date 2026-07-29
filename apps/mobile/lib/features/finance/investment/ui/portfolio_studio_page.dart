part of 'portfolio_hub_page.dart';

enum _PortfolioStudioSection { overview, structure, assets, rules }

class _PortfolioPlanStrip extends ConsumerWidget {
  const _PortfolioPlanStrip({
    required this.portfolios,
    required this.tree,
    required this.actualWeights,
  });

  final List<InvestmentPortfolio> portfolios;
  final PortfolioAllocationTree tree;
  final Map<String, double> actualWeights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portfolioById = {for (final item in portfolios) item.id: item};
    final nodes = tree.childrenOf(tree.root.id);
    if (nodes.isEmpty) {
      return SoftCard.raised(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.portfolioStudioPlanTitle,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.portfolioStudioPlanEmptyHint,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s12),
            FButton(
              onPress: () => showInvestmentPortfolioFormSheet(context),
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.portfolioCreateTitle),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioStudioPlanTitle,
          subtitle: l10n.portfolioStudioPlanHint,
          action: nodes.length > 1
              ? FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () async {
                    final targets =
                        ref
                            .read(activeUniversePortfolioTargetsProvider)
                            .value ??
                        const <PortfolioAllocationTarget>[];
                    if (targets.isEmpty) return;
                    await showPortfolioAllocationEditor(
                      context,
                      ref,
                      portfolios: portfolios,
                      targets: targets,
                    );
                  },
                  child: Text(l10n.capitalAllocationEditAction),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.s8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: nodes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s8),
            itemBuilder: (context, index) {
              if (index == nodes.length) {
                return SizedBox(
                  width: 112,
                  child: FButton(
                    variant: FButtonVariant.outline,
                    onPress: () => showInvestmentPortfolioFormSheet(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FLucideIcons.plus),
                        const SizedBox(height: AppSpacing.s6),
                        Text(l10n.portfolioCreateTitle),
                      ],
                    ),
                  ),
                );
              }
              final node = nodes[index];
              final portfolio = portfolioById[node.referenceId];
              final actual = actualWeights[portfolio?.id];
              final drift = actual == null
                  ? null
                  : (actual - node.targetWeight).abs();
              return SizedBox(
                width: 184,
                child: AppTappable(
                  onPress: portfolio == null
                      ? null
                      : () => context.push(
                          FinanceRoutes.wealthPortfolioStudioFor(portfolio.id),
                        ),
                  child: SoftCard.raised(
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                node.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.labelStyle,
                              ),
                            ),
                            const Icon(
                              FLucideIcons.chevronRight,
                              size: AppIconSizes.sm,
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_studioPercentFromBps(node.targetWeightBps)}%',
                                    style: context.theme.typography.body.lg,
                                  ),
                                  Text(
                                    actual == null
                                        ? l10n.portfolioStudioPlanTargetLabel
                                        : l10n.rebalancePortfolioWeightPair(
                                            _studioPercent(actual),
                                            _studioPercent(node.targetWeight),
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.captionStyle,
                                  ),
                                ],
                              ),
                            ),
                            if (drift case final value?)
                              Icon(
                                value <= node.driftBandBps / 10000
                                    ? FLucideIcons.circleCheck
                                    : FLucideIcons.triangleAlert,
                                size: AppIconSizes.sm,
                                color: value <= node.driftBandBps / 10000
                                    ? context.theme.colors.primary
                                    : context.theme.colors.destructive,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PortfolioStudioPage extends ConsumerStatefulWidget {
  const PortfolioStudioPage({super.key, required this.portfolioId});

  final String portfolioId;

  @override
  ConsumerState<PortfolioStudioPage> createState() =>
      _PortfolioStudioPageState();
}

class _PortfolioStudioPageState extends ConsumerState<PortfolioStudioPage> {
  _PortfolioStudioSection _section = _PortfolioStudioSection.overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final portfolios = ref.watch(investmentPortfoliosProvider);
    final tree = ref.watch(portfolioAllocationTreeProvider);
    final portfolio = portfolios.value
        ?.where((item) => item.id == widget.portfolioId)
        .firstOrNull;

    return AppPageScaffold(
      title: portfolio?.name ?? l10n.portfolioStudioTitle,
      actions: [
        if (portfolio != null)
          AppHeaderAction(
            semanticsLabel: l10n.portfolioEditTitle,
            icon: const Icon(FLucideIcons.settings2),
            onPress: () =>
                showInvestmentPortfolioFormSheet(context, existing: portfolio),
          ),
      ],
      childPad: false,
      child: switch ((portfolios, tree)) {
        (AsyncData(), AsyncData(value: final allocationTree))
            when portfolio != null && allocationTree != null =>
          _PortfolioStudioBody(
            portfolio: portfolio,
            tree: allocationTree,
            section: _section,
            onSectionChanged: (next) => setState(() => _section = next),
          ),
        (AsyncError(:final error, :final stackTrace), _) ||
        (_, AsyncError(:final error, :final stackTrace)) => kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () {
            ref.invalidate(investmentPortfoliosProvider);
            ref.invalidate(portfolioAllocationTreeProvider);
          },
        ),
        (AsyncData(), AsyncData()) => AppEmptyState(
          icon: FLucideIcons.layers,
          title: l10n.portfolioStudioNotFound,
          action: FButton(
            variant: FButtonVariant.outline,
            onPress: () => context.go(FinanceRoutes.wealthPortfolio),
            child: Text(l10n.portfolioHubTitle),
          ),
        ),
        _ => const _PortfolioHubSkeleton(),
      },
    );
  }
}

class _PortfolioStudioBody extends StatelessWidget {
  const _PortfolioStudioBody({
    required this.portfolio,
    required this.tree,
    required this.section,
    required this.onSectionChanged,
  });

  final InvestmentPortfolio portfolio;
  final PortfolioAllocationTree tree;
  final _PortfolioStudioSection section;
  final ValueChanged<_PortfolioStudioSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final portfolioNode = tree.nodeForReference(
      AllocationNodeType.portfolio,
      portfolio.id,
    );
    if (portfolioNode == null) {
      return const SizedBox.shrink();
    }
    final sleeves = tree.childrenOf(portfolioNode.id);
    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.page,
      expandSinglePrimary: true,
      padding: shellTabContentPadding(
        context,
        left: AppSpacing.s16,
        top: AppSpacing.s8,
        right: AppSpacing.s16,
        bottom: AppSpacing.s24,
      ),
      primary: ListView(
        children: [
          _StudioHero(
            portfolio: portfolio,
            portfolioNode: portfolioNode,
            sleeves: sleeves,
            tree: tree,
          ),
          const SizedBox(height: AppSpacing.s16),
          _StudioSectionSegment(value: section, onChanged: onSectionChanged),
          const SizedBox(height: AppSpacing.s16),
          switch (section) {
            _PortfolioStudioSection.overview => _StudioOverview(
              portfolio: portfolio,
              portfolioNode: portfolioNode,
              sleeves: sleeves,
              tree: tree,
            ),
            _PortfolioStudioSection.structure => _StudioStructure(
              portfolio: portfolio,
              sleeves: sleeves,
              tree: tree,
            ),
            _PortfolioStudioSection.assets => _StudioAssets(
              portfolio: portfolio,
              sleeves: sleeves,
              tree: tree,
            ),
            _PortfolioStudioSection.rules => _StudioRules(
              portfolio: portfolio,
              sleeves: sleeves,
              tree: tree,
            ),
          },
        ],
      ),
    );
  }
}

class _StudioHero extends StatelessWidget {
  const _StudioHero({
    required this.portfolio,
    required this.portfolioNode,
    required this.sleeves,
    required this.tree,
  });

  final InvestmentPortfolio portfolio;
  final AllocationNode portfolioNode;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final included = sleeves.fold<int>(
      0,
      (count, sleeve) => count + tree.inclusionsFor(sleeve.id).length,
    );
    final rules = sleeves.fold<int>(
      0,
      (count, sleeve) =>
          count +
          tree
              .attachmentsFor(sleeve.id)
              .where((attachment) => !attachment.isPrimary)
              .length,
    );
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: FLucideIcons.chartNoAxesCombined,
                color: context.theme.colors.primary,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      portfolio.name,
                      style: context.theme.typography.body.lg,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      l10n.portfolioStudioTargetSummary(
                        _studioPercentFromBps(portfolioNode.targetWeightBps),
                        sleeves.length,
                      ),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              _StudioStatusPill(label: l10n.portfolioStudioConfiguredStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioSleevesMetric,
                  value: '${sleeves.length}',
                ),
              ),
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioAssetsMetric,
                  value: '$included',
                ),
              ),
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioRulesMetric,
                  value: '$rules',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          FButton(
            onPress: () => context.push(FinanceRoutes.planRebalance),
            prefix: const Icon(FLucideIcons.scale),
            child: Text(l10n.portfolioStudioRebalanceAction),
          ),
        ],
      ),
    );
  }
}

class _StudioSectionSegment extends StatelessWidget {
  const _StudioSectionSegment({required this.value, required this.onChanged});

  final _PortfolioStudioSection value;
  final ValueChanged<_PortfolioStudioSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<_PortfolioStudioSection>(
      options: _PortfolioStudioSection.values,
      value: value,
      labelOf: (item) => switch (item) {
        _PortfolioStudioSection.overview => l10n.portfolioStudioOverviewTab,
        _PortfolioStudioSection.structure => l10n.portfolioStudioStructureTab,
        _PortfolioStudioSection.assets => l10n.portfolioStudioAssetsTab,
        _PortfolioStudioSection.rules => l10n.portfolioStudioRulesTab,
      },
      onChanged: onChanged,
    );
  }
}

class _StudioOverview extends ConsumerWidget {
  const _StudioOverview({
    required this.portfolio,
    required this.portfolioNode,
    required this.sleeves,
    required this.tree,
  });

  final InvestmentPortfolio portfolio;
  final AllocationNode portfolioNode;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioStudioAllocationTitle,
          subtitle: l10n.portfolioStudioAllocationHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        _AllocationPathCard(
          portfolioNode: portfolioNode,
          sleeves: sleeves,
          tree: tree,
        ),
        const SizedBox(height: AppSpacing.s16),
        _StudioSectionHeader(
          title: l10n.portfolioStudioNextActionTitle,
          subtitle: l10n.portfolioStudioNextActionHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () async {
            final groups = await ref.read(
              portfolioRebalanceGroupsProvider.future,
            );
            final scoped = groups
                .where((group) => group.portfolioId == portfolio.id)
                .toList(growable: false);
            if (!context.mounted || scoped.isEmpty) return;
            await showStrategySleeveAllocationEditor(context, ref, scoped);
          },
          prefix: const Icon(FLucideIcons.slidersHorizontal),
          child: Text(l10n.portfolioStrategyAllocationEditTitle),
        ),
      ],
    );
  }
}

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

class _StudioAssets extends ConsumerWidget {
  const _StudioAssets({
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
    final lots = ref.watch(allInvestmentLotsProvider).value ?? const <Lot>[];
    final assets = ref.watch(allAssetsStreamProvider).value ?? const <Asset>[];
    final accounts =
        ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final lotById = {for (final lot in lots) lot.id: lot};
    final assetById = {for (final asset in assets) asset.id: asset};
    final accountById = {for (final account in accounts) account.id: account};
    final targets = [
      for (final sleeve in sleeves)
        for (final target in tree.childrenOf(sleeve.id))
          if (target.type == AllocationNodeType.asset)
            (sleeve: sleeve, target: target),
    ];
    final inclusions = [
      for (final sleeve in sleeves)
        for (final inclusion in tree.inclusionsFor(sleeve.id))
          (sleeve: sleeve, inclusion: inclusion),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.targetAllocationEditorAssetTargets,
          subtitle: l10n.portfolioStudioAssetTargetsHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        if (targets.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.crosshair,
            title: l10n.targetAllocationEditorNoAssetTargets,
          )
        else
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < targets.length; index++) ...[
                  _StudioAssetTargetTile(item: targets[index]),
                  if (index != targets.length - 1)
                    const AppGroupedDivider(
                      indent: AppSpacing.s12,
                      endIndent: AppSpacing.s12,
                    ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s20),
        _StudioSectionHeader(
          title: l10n.portfolioStudioIncludedAssetsTitle,
          subtitle: l10n.portfolioStudioIncludedAssetsHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        if (inclusions.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.listChecks,
            title: l10n.portfolioStudioNoIncludedAssets,
          )
        else
          AppGroupedSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < inclusions.length; index++) ...[
                  _CapitalInclusionTile(
                    item: inclusions[index],
                    lotById: lotById,
                    assetById: assetById,
                    accountById: accountById,
                  ),
                  if (index != inclusions.length - 1)
                    const AppGroupedDivider(
                      indent: AppSpacing.s12,
                      endIndent: AppSpacing.s12,
                    ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: FButton(
                onPress: () => showPortfolioLotAssignmentSheet(context),
                prefix: const Icon(FLucideIcons.briefcaseBusiness),
                child: Text(l10n.portfolioStudioIncludePositionAction),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: FButton(
                variant: FButtonVariant.outline,
                onPress: () => showPortfolioCashAssignmentSheet(context),
                prefix: const Icon(FLucideIcons.walletCards),
                child: Text(l10n.portfolioStudioIncludeCashAction),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StudioAssetTargetTile extends StatelessWidget {
  const _StudioAssetTargetTile({required this.item});

  final ({AllocationNode sleeve, AllocationNode target}) item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = item.target.assetCategory;
    final categoryTarget =
        item.target.assetKind == AllocationAssetKind.category &&
        category != null;
    final label = categoryTarget
        ? AssetCategoryVisuals.label(l10n, category)
        : item.target.name;
    return FTile(
      prefix: Icon(
        category == null
            ? FLucideIcons.chartNoAxesCombined
            : AssetCategoryVisuals.icon(category),
      ),
      title: Text(label),
      subtitle: Text(item.sleeve.name),
      suffix: Text(
        '${_studioPercentFromBps(item.target.targetWeightBps)}%',
        style: TypographyTokens.numericBodyStrong,
      ),
    );
  }
}

class _CapitalInclusionTile extends ConsumerWidget {
  const _CapitalInclusionTile({
    required this.item,
    required this.lotById,
    required this.assetById,
    required this.accountById,
  });

  final ({AllocationNode sleeve, CapitalInclusion inclusion}) item;
  final Map<String, Lot> lotById;
  final Map<String, Asset> assetById;
  final Map<String, Account> accountById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final assignment = item.inclusion.assignment;
    final lot = assignment.sourceKind == PortfolioCapitalSourceKind.lot
        ? lotById[assignment.sourceId]
        : null;
    final asset = lot == null ? null : assetById[lot.assetId];
    final account = assignment.sourceKind == PortfolioCapitalSourceKind.lot
        ? accountById[lot?.accountId]
        : accountById[assignment.sourceId];

    if (assignment.sourceKind == PortfolioCapitalSourceKind.cashAccount) {
      final amount = assignment.amount ?? Decimal.zero;
      final currency = assignment.currency ?? account?.currency;
      return FTile(
        prefix: const Icon(FLucideIcons.walletCards),
        title: Text(account?.name ?? l10n.portfolioHubAssetTypeCash),
        subtitle: Text(item.sleeve.name),
        suffix: _StudioAssetValue(
          value: currency == null
              ? amount.toString()
              : formatters.currency(amount, code: currency),
          label: l10n.portfolioHubAssetTypeCash,
        ),
      );
    }

    final quantity = assignment.quantity ?? lot?.remainingQuantity;
    final costBasis = quantity == null || lot == null
        ? null
        : quantity * lot.costPerUnit;
    final assetName = asset?.name?.trim();
    final title = asset == null
        ? l10n.portfolioStudioIncludedPositionLabel
        : asset.symbol;
    final details = <String>[
      if (assetName != null &&
          assetName.isNotEmpty &&
          assetName.toUpperCase() != asset!.symbol.toUpperCase())
        assetName,
      item.sleeve.name,
      if (quantity != null)
        '${l10n.tradeEntryQuantityLabel} ${formatters.number(quantity.toDouble())}',
      if (account != null) account.name,
    ];
    return FTile(
      prefix: const Icon(FLucideIcons.chartCandlestick),
      title: Text(title),
      subtitle: Text(details.join(' · ')),
      suffix: costBasis == null || lot == null
          ? null
          : _StudioAssetValue(
              value: formatters.currency(costBasis, code: lot.currency),
              label: l10n.portfolioHubCostBasisLabel,
            ),
    );
  }
}

class _StudioAssetValue extends StatelessWidget {
  const _StudioAssetValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TypographyTokens.numericBodyStrong,
          textAlign: TextAlign.end,
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(label, style: context.captionStyle, textAlign: TextAlign.end),
      ],
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

class _AllocationPathCard extends StatelessWidget {
  const _AllocationPathCard({
    required this.portfolioNode,
    required this.sleeves,
    required this.tree,
  });

  final AllocationNode portfolioNode;
  final List<AllocationNode> sleeves;
  final PortfolioAllocationTree tree;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AllocationPathRow(
            icon: FLucideIcons.briefcaseBusiness,
            title: portfolioNode.name,
            trailing:
                '${_studioPercentFromBps(portfolioNode.targetWeightBps)}%',
          ),
          for (final sleeve in sleeves) ...[
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.s16),
              child: SizedBox(
                height: AppSpacing.s12,
                child: VerticalDivider(width: 1),
              ),
            ),
            _AllocationPathRow(
              icon: FLucideIcons.layers3,
              title: sleeve.name,
              subtitle: l10n.portfolioStudioAssetTargetCount(
                tree.childrenOf(sleeve.id).length,
              ),
              trailing: '${_studioPercentFromBps(sleeve.targetWeightBps)}%',
              inset: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationPathRow extends StatelessWidget {
  const _AllocationPathRow({
    required this.icon,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.inset = false,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final String? subtitle;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: inset ? AppSpacing.s16 : 0),
      child: Row(
        children: [
          AppIconTile(icon: icon, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.labelStyle),
                if (subtitle case final value?) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(value, style: context.captionStyle),
                ],
              ],
            ),
          ),
          Text(trailing, style: context.captionLabelStyle),
        ],
      ),
    );
  }
}

class _StudioSectionHeader extends StatelessWidget {
  const _StudioSectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.theme.typography.body.sm),
              const SizedBox(height: AppSpacing.s4),
              Text(subtitle, style: context.captionStyle),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _StudioMetric extends StatelessWidget {
  const _StudioMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.theme.typography.body.lg),
        const SizedBox(height: AppSpacing.s2),
        Text(label, style: context.captionStyle),
      ],
    );
  }
}

class _StudioStatusPill extends StatelessWidget {
  const _StudioStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.primary.withValues(alpha: 0.12),
        borderRadius: context.theme.style.borderRadius.pill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        child: Text(
          label,
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.primary,
          ),
        ),
      ),
    );
  }
}

String _studioPercentFromBps(int bps) {
  final value = bps / 100;
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

String _studioPercent(double value) {
  final percent = value * 100;
  return '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%';
}

String _studioTransferPolicyLabel(
  AppLocalizations l10n,
  GroupTransferPolicy policy,
) => switch (policy) {
  GroupTransferPolicy.bidirectional => l10n.portfolioGroupTransferBidirectional,
  GroupTransferPolicy.inflowsOnly => l10n.portfolioGroupTransferInflowsOnly,
  GroupTransferPolicy.isolated => l10n.portfolioGroupTransferIsolated,
};
