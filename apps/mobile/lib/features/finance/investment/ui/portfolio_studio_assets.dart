part of 'portfolio_hub_page.dart';

enum _PortfolioAssetSource { positions, cash }

Future<void> _showPortfolioAssetSourceSheet(
  BuildContext context, {
  String? preferredGroupId,
  Decimal? suggestedAmount,
}) async {
  final l10n = AppLocalizations.of(context);
  final source = await showAppSheet<_PortfolioAssetSource>(
    context: context,
    title: l10n.portfolioStudioAddAssetsAction,
    subtitle: l10n.portfolioStudioAddAssetsHint,
    builder: (sheetContext) => AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FTile(
            prefix: const Icon(FLucideIcons.briefcaseBusiness),
            title: Text(l10n.portfolioStudioIncludePositionAction),
            suffix: const Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
            ),
            onPress: () =>
                Navigator.of(sheetContext).pop(_PortfolioAssetSource.positions),
          ),
          const AppGroupedDivider(
            indent: AppSpacing.s12,
            endIndent: AppSpacing.s12,
          ),
          FTile(
            prefix: const Icon(FLucideIcons.walletCards),
            title: Text(l10n.portfolioStudioIncludeCashAction),
            suffix: const Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
            ),
            onPress: () =>
                Navigator.of(sheetContext).pop(_PortfolioAssetSource.cash),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || source == null) return;
  switch (source) {
    case _PortfolioAssetSource.positions:
      await showPortfolioLotAssignmentSheet(
        context,
        preferredGroupId: preferredGroupId,
      );
    case _PortfolioAssetSource.cash:
      await showPortfolioCashAssignmentSheet(
        context,
        preferredGroupId: preferredGroupId,
        suggestedAmount: suggestedAmount,
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
            action: FButton(
              onPress: () async {
                if (sleeves.isEmpty) {
                  await showAddStrategySleeve(
                    context,
                    portfolioId: portfolio.id,
                  );
                  return;
                }
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
              child: Text(
                sleeves.isEmpty
                    ? l10n.portfolioGroupAddAction
                    : l10n.portfolioStrategyAllocationEditTitle,
              ),
            ),
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
            action: FButton(
              onPress: () => _showPortfolioAssetSourceSheet(context),
              prefix: const Icon(FLucideIcons.plus),
              child: Text(l10n.portfolioStudioAddAssetsAction),
            ),
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
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => _showPortfolioAssetSourceSheet(context),
          prefix: const Icon(FLucideIcons.plus),
          child: Text(l10n.portfolioStudioAddAssetsAction),
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
