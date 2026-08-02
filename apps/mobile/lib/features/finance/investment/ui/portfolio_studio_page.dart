part of 'portfolio_hub_page.dart';

class PortfolioStudioPage extends ConsumerStatefulWidget {
  const PortfolioStudioPage({
    super.key,
    required this.portfolioId,
    this.initialSection = PortfolioStudioSection.overview,
    this.transferIntent,
  });

  final String portfolioId;
  final PortfolioStudioSection initialSection;
  final CapitalTransferIntent? transferIntent;

  @override
  ConsumerState<PortfolioStudioPage> createState() =>
      _PortfolioStudioPageState();
}

class _PortfolioStudioPageState extends ConsumerState<PortfolioStudioPage> {
  late PortfolioStudioSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

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
            transferIntent: widget.transferIntent,
            portfolioNames: {
              for (final item in portfolios.requireValue) item.id: item.name,
            },
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
    required this.transferIntent,
    required this.portfolioNames,
    required this.onSectionChanged,
  });

  final InvestmentPortfolio portfolio;
  final PortfolioAllocationTree tree;
  final PortfolioStudioSection section;
  final CapitalTransferIntent? transferIntent;
  final Map<String, String> portfolioNames;
  final ValueChanged<PortfolioStudioSection> onSectionChanged;

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
          if (transferIntent != null) ...[
            _StudioTransferTask(
              intent: transferIntent!,
              tree: tree,
              portfolioNames: portfolioNames,
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          _StudioHero(
            portfolio: portfolio,
            portfolioNode: portfolioNode,
            sleeves: sleeves,
            tree: tree,
          ),
          const SizedBox(height: AppSpacing.s20),
          if (section == PortfolioStudioSection.overview) ...[
            _StudioOverview(
              portfolio: portfolio,
              portfolioNode: portfolioNode,
              sleeves: sleeves,
              tree: tree,
            ),
            const SizedBox(height: AppSpacing.s20),
            _StudioConfigurationList(
              summary: PortfolioStudioSummary.fromTree(
                tree: tree,
                sleeves: sleeves,
              ),
              onSelected: onSectionChanged,
            ),
          ] else ...[
            _StudioDrillInHeader(
              section: section,
              onBack: () => onSectionChanged(PortfolioStudioSection.overview),
            ),
            const SizedBox(height: AppSpacing.s12),
            switch (section) {
              PortfolioStudioSection.overview => const SizedBox.shrink(),
              PortfolioStudioSection.structure => _StudioStructure(
                portfolio: portfolio,
                sleeves: sleeves,
                tree: tree,
              ),
              PortfolioStudioSection.assets => _StudioAssets(
                portfolio: portfolio,
                sleeves: sleeves,
                tree: tree,
              ),
              PortfolioStudioSection.rules => _StudioRules(
                portfolio: portfolio,
                sleeves: sleeves,
                tree: tree,
              ),
            },
          ],
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
    final summary = PortfolioStudioSummary.fromTree(
      tree: tree,
      sleeves: sleeves,
    );
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.portfolioStudioTargetSummary(
                    _studioPercentFromBps(portfolioNode.targetWeightBps),
                    summary.sleeveCount,
                  ),
                  style: context.captionStyle,
                ),
              ),
              _StudioStatusPill(label: l10n.portfolioStudioConfiguredStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioSleevesMetric,
                  value: '${summary.sleeveCount}',
                ),
              ),
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioAssetsMetric,
                  value: '${summary.includedAssetCount}',
                ),
              ),
              Expanded(
                child: _StudioMetric(
                  label: l10n.portfolioStudioRulesMetric,
                  value: '${summary.secondaryRuleCount}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudioConfigurationList extends StatelessWidget {
  const _StudioConfigurationList({
    required this.summary,
    required this.onSelected,
  });

  final PortfolioStudioSummary summary;
  final ValueChanged<PortfolioStudioSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (
        section: PortfolioStudioSection.structure,
        icon: FLucideIcons.layers3,
        title: l10n.portfolioStudioStructureTab,
        subtitle: l10n.portfolioStudioSleeveCount(summary.sleeveCount),
      ),
      (
        section: PortfolioStudioSection.assets,
        icon: FLucideIcons.walletCards,
        title: l10n.portfolioStudioAssetsTab,
        subtitle: l10n.portfolioStudioIncludedAssetCount(
          summary.includedAssetCount,
        ),
      ),
      (
        section: PortfolioStudioSection.rules,
        icon: FLucideIcons.listChecks,
        title: l10n.portfolioStudioRulesTab,
        subtitle: l10n.portfolioStudioRuleCount(summary.secondaryRuleCount),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioStudioConfigurationTitle,
          subtitle: l10n.portfolioStudioConfigurationHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                FTile(
                  prefix: Icon(items[index].icon),
                  title: Text(items[index].title),
                  subtitle: Text(items[index].subtitle),
                  suffix: const Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.sm,
                  ),
                  onPress: () => onSelected(items[index].section),
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
      ],
    );
  }
}

class _StudioDrillInHeader extends StatelessWidget {
  const _StudioDrillInHeader({required this.section, required this.onBack});

  final PortfolioStudioSection section;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (section) {
      PortfolioStudioSection.overview => l10n.portfolioStudioOverviewTab,
      PortfolioStudioSection.structure => l10n.portfolioStudioStructureTab,
      PortfolioStudioSection.assets => l10n.portfolioStudioAssetsTab,
      PortfolioStudioSection.rules => l10n.portfolioStudioRulesTab,
    };
    return FButton(
      variant: FButtonVariant.ghost,
      onPress: onBack,
      prefix: const Icon(FLucideIcons.arrowLeft),
      child: Align(alignment: Alignment.centerLeft, child: Text(title)),
    );
  }
}

class _StudioTransferTask extends ConsumerWidget {
  const _StudioTransferTask({
    required this.intent,
    required this.tree,
    required this.portfolioNames,
  });

  final CapitalTransferIntent intent;
  final PortfolioAllocationTree tree;
  final Map<String, String> portfolioNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final task = PortfolioTransferTaskProjection.fromIntent(
      intent: intent,
      tree: tree,
      portfolioNames: portfolioNames,
    );
    final amount = formatters.currency(
      task.amount ?? Decimal.zero,
      code: intent.currency,
    );
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.theme.colors.primary.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  FLucideIcons.arrowRightLeft,
                  size: AppIconSizes.md,
                  color: context.theme.colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.rebalanceTransferTaskTitle,
                      style: context.theme.typography.body.sm,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      l10n.rebalanceTransferTaskSummary(
                        task.fromName,
                        task.toName,
                        amount,
                      ),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(l10n.rebalanceTransferTaskHint, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            onPress: () => _showPortfolioAssetSourceSheet(
              context,
              preferredGroupId: task.preferredGroupId,
              suggestedAmount: task.amount,
            ),
            prefix: const Icon(FLucideIcons.plus),
            child: Text(l10n.portfolioStudioAddAssetsAction),
          ),
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => context.go(FinanceRoutes.planRebalance),
            prefix: const Icon(FLucideIcons.refreshCw),
            child: Text(l10n.rebalanceTransferTaskRecalculateAction),
          ),
        ],
      ),
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
      padding: EdgeInsets.only(left: inset ? AppSpacing.s16 : AppSpacing.s0),
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
        color: context.theme.colors.primary.withValues(alpha: AppOpacity.light),
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
