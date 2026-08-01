part of 'portfolio_hub_page.dart';

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
    final trends = ref.watch(portfolioMonthlyTrendSummariesProvider);
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
          height: AppControlHeights.portfolioOverviewRail,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: nodes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s8),
            itemBuilder: (context, index) {
              if (index == nodes.length) {
                return SizedBox(
                  width: AppControlWidths.portfolioCreateCard,
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
              final trend = portfolio == null
                  ? null
                  : trends.value?[portfolio.id];
              final trendPending = trends.isLoading && !trends.hasValue;
              return SizedBox(
                width: AppControlWidths.portfolioOverviewCard,
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
                        const SizedBox(height: AppSpacing.s8),
                        if (trendPending)
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SkeletonBox(height: AppSpacing.s40),
                            ),
                          )
                        else if (trend == null)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.portfolioTrendAwaitingData,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.microCaptionStyle,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: _PortfolioTrendSparkline(series: trend),
                          ),
                        const SizedBox(height: AppSpacing.s6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (trend != null)
                                    MoneyText(
                                      amount: trend.currentValue.toDouble(),
                                      currencyCode: trend.baseCurrency,
                                      compact: true,
                                      style: TypographyTokens.numericBodyStrong,
                                    )
                                  else
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
                            if (trend?.periodPerformanceRatio case final ratio?)
                              DeltaText.percentFromRatio(
                                ratio: ratio,
                                fractionDigits: 1,
                                showIcon: false,
                                style: context.microCaptionStyle,
                              )
                            else if (drift case final value?)
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

class _PortfolioTrendSparkline extends StatelessWidget {
  const _PortfolioTrendSparkline({required this.series});

  final PortfolioTrendSeries series;

  @override
  Widget build(BuildContext context) {
    final points = series.points
        .skipWhile((point) => point.marketValueInBase <= Decimal.zero)
        .map(
          (point) => ChartPoint(
            x: point.asOf.millisecondsSinceEpoch.toDouble(),
            y: point.performanceRatio * 100,
            meta: point,
          ),
        )
        .toList(growable: false);
    if (points.length < 2) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          AppLocalizations.of(context).portfolioTrendAwaitingData,
          style: context.microCaptionStyle,
        ),
      );
    }
    final ratio = series.periodPerformanceRatio ?? 0;
    return NwLineChart(
      series: [
        ChartSeries(
          name: AppLocalizations.of(context).portfolioTrendPerformance,
          points: points,
          intent: ratio < 0 ? SeriesIntent.down : SeriesIntent.up,
          fillOpacity: AppOpacity.light,
        ),
      ],
      minimal: true,
      filled: true,
      curved: true,
      showDots: false,
      heroDots: true,
      semanticLabel: AppLocalizations.of(context).portfolioTrendMonthSemantics,
    );
  }
}

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
          const SizedBox(height: AppSpacing.s16),
          _StudioSectionSegment(value: section, onChanged: onSectionChanged),
          const SizedBox(height: AppSpacing.s16),
          switch (section) {
            PortfolioStudioSection.overview => _StudioOverview(
              portfolio: portfolio,
              portfolioNode: portfolioNode,
              sleeves: sleeves,
              tree: tree,
            ),
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
                        summary.sleeveCount,
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
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < Breakpoints.formColumn;
              final positions = FButton(
                onPress: () => showPortfolioLotAssignmentSheet(
                  context,
                  preferredGroupId: task.preferredGroupId,
                ),
                prefix: const Icon(FLucideIcons.briefcaseBusiness),
                child: Text(l10n.portfolioStudioIncludePositionAction),
              );
              final cash = FButton(
                variant: FButtonVariant.outline,
                onPress: () => showPortfolioCashAssignmentSheet(
                  context,
                  preferredGroupId: task.preferredGroupId,
                  suggestedAmount: task.amount,
                ),
                prefix: const Icon(FLucideIcons.walletCards),
                child: Text(l10n.portfolioStudioIncludeCashAction),
              );
              final children = [positions, cash];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    children.first,
                    const SizedBox(height: AppSpacing.s8),
                    children.last,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: children.first),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(child: children.last),
                ],
              );
            },
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

class _StudioSectionSegment extends StatelessWidget {
  const _StudioSectionSegment({required this.value, required this.onChanged});

  final PortfolioStudioSection value;
  final ValueChanged<PortfolioStudioSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppAdaptiveChoice<PortfolioStudioSection>(
      title: l10n.portfolioStudioTitle,
      options: PortfolioStudioSection.values,
      value: value,
      labelOf: (item) => switch (item) {
        PortfolioStudioSection.overview => l10n.portfolioStudioOverviewTab,
        PortfolioStudioSection.structure => l10n.portfolioStudioStructureTab,
        PortfolioStudioSection.assets => l10n.portfolioStudioAssetsTab,
        PortfolioStudioSection.rules => l10n.portfolioStudioRulesTab,
      },
      iconOf: (item) => switch (item) {
        PortfolioStudioSection.overview => FLucideIcons.layoutDashboard,
        PortfolioStudioSection.structure => FLucideIcons.network,
        PortfolioStudioSection.assets => FLucideIcons.walletCards,
        PortfolioStudioSection.rules => FLucideIcons.listChecks,
      },
      onChanged: onChanged,
    );
  }
}

class _StudioOverview extends ConsumerStatefulWidget {
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
  ConsumerState<_StudioOverview> createState() => _StudioOverviewState();
}

class _StudioOverviewState extends ConsumerState<_StudioOverview> {
  PortfolioTrendRange _range = PortfolioTrendRange.month;
  PortfolioTrendMetric _metric = PortfolioTrendMetric.marketValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trend = ref.watch(
      portfolioTrendProvider(
        PortfolioTrendRequest(portfolioId: widget.portfolio.id, range: _range),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioSectionHeader(
          title: l10n.portfolioTrendTitle,
          subtitle: l10n.portfolioTrendHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        SoftCard.raised(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: _PortfolioTrendPanel(
            trend: trend,
            metric: _metric,
            range: _range,
            onMetricChanged: (metric) => setState(() => _metric = metric),
            onRangeChanged: (range) => setState(() => _range = range),
            onRetry: () => ref.invalidate(
              portfolioTrendProvider(
                PortfolioTrendRequest(
                  portfolioId: widget.portfolio.id,
                  range: _range,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        _StudioSectionHeader(
          title: l10n.portfolioStudioAllocationTitle,
          subtitle: l10n.portfolioStudioAllocationHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        _AllocationPathCard(
          portfolioNode: widget.portfolioNode,
          sleeves: widget.sleeves,
          tree: widget.tree,
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
                .where((group) => group.portfolioId == widget.portfolio.id)
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

class _PortfolioTrendPanel extends StatelessWidget {
  const _PortfolioTrendPanel({
    required this.trend,
    required this.metric,
    required this.range,
    required this.onMetricChanged,
    required this.onRangeChanged,
    required this.onRetry,
  });

  final AsyncValue<PortfolioTrendSeries?> trend;
  final PortfolioTrendMetric metric;
  final PortfolioTrendRange range;
  final ValueChanged<PortfolioTrendMetric> onMetricChanged;
  final ValueChanged<PortfolioTrendRange> onRangeChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedRow<PortfolioTrendMetric>(
          options: PortfolioTrendMetric.values,
          value: metric,
          minSegmentWidth: 88,
          labelOf: (item) => switch (item) {
            PortfolioTrendMetric.marketValue => l10n.portfolioTrendMarketValue,
            PortfolioTrendMetric.performance => l10n.portfolioTrendPerformance,
          },
          onChanged: onMetricChanged,
        ),
        const SizedBox(height: AppSpacing.s16),
        ContentCrossFade(
          child: KeyedSubtree(
            key: ValueKey('${range.name}-${metric.name}'),
            child: trend.when(
              loading: () => const _PortfolioTrendSkeleton(),
              error: (_, _) => _PortfolioTrendError(onRetry: onRetry),
              data: (series) => series == null
                  ? const _PortfolioTrendEmpty()
                  : _PortfolioTrendChart(series: series, metric: metric),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        SegmentedRow<PortfolioTrendRange>(
          options: PortfolioTrendRange.values,
          value: range,
          minSegmentWidth: 48,
          labelOf: (item) => switch (item) {
            PortfolioTrendRange.month => l10n.dashboardRange1M,
            PortfolioTrendRange.quarter => l10n.dashboardRange3M,
            PortfolioTrendRange.yearToDate => l10n.portfolioTrendRangeYtd,
            PortfolioTrendRange.year => l10n.dashboardRange1Y,
            PortfolioTrendRange.all => l10n.dashboardRangeAll,
          },
          onChanged: onRangeChanged,
        ),
      ],
    );
  }
}

class _PortfolioTrendChart extends StatelessWidget {
  const _PortfolioTrendChart({required this.series, required this.metric});

  final PortfolioTrendSeries series;
  final PortfolioTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final funded = series.points
        .skipWhile((point) => point.marketValueInBase <= Decimal.zero)
        .toList(growable: false);
    if (funded.length < 2) {
      return const _PortfolioTrendEmpty();
    }

    final chartPoints = [
      for (final point in funded)
        ChartPoint(
          x: point.asOf.millisecondsSinceEpoch.toDouble(),
          y: switch (metric) {
            PortfolioTrendMetric.marketValue =>
              point.marketValueInBase.toDouble(),
            PortfolioTrendMetric.performance => point.performanceRatio * 100,
          },
          meta: point,
        ),
    ];
    final periodPerformance = series.periodPerformanceRatio;
    final changeIntent = switch (periodPerformance) {
      final ratio? when ratio < 0 => SeriesIntent.down,
      _ => SeriesIntent.up,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendCurrentValue,
                child: MoneyText(
                  amount: series.currentValue.toDouble(),
                  currencyCode: series.baseCurrency,
                  compact: true,
                  style: TypographyTokens.numericTitleStrong,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendPeriodPerformance,
                child: periodPerformance == null
                    ? Text('—', style: TypographyTokens.numericBodyStrong)
                    : DeltaText.percentFromRatio(
                        ratio: periodPerformance,
                        fractionDigits: 1,
                        showIcon: false,
                        style: TypographyTokens.numericBodyStrong,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _PortfolioTrendMetric(
                label: l10n.portfolioTrendNetFlow,
                child: DeltaText(
                  value: series.periodNetFlow.toDouble(),
                  format: DeltaFormat.currency,
                  currencyCode: series.baseCurrency,
                  fractionDigits: 0,
                  showIcon: false,
                  style: TypographyTokens.numericBodyStrong,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        SizedBox(
          key: const ValueKey('portfolio-trend-chart'),
          height: AppChartHeights.standard,
          child: NwLineChart(
            series: [
              ChartSeries(
                name: metric == PortfolioTrendMetric.marketValue
                    ? l10n.portfolioTrendMarketValue
                    : l10n.portfolioTrendPerformance,
                points: chartPoints,
                intent: changeIntent,
                fillOpacity: AppOpacity.light,
              ),
            ],
            xAxis: TimeAxis(
              format: switch (series.range) {
                PortfolioTrendRange.month ||
                PortfolioTrendRange.quarter => AxisDateFormat.dayMonth,
                PortfolioTrendRange.yearToDate ||
                PortfolioTrendRange.year => AxisDateFormat.monthYear,
                PortfolioTrendRange.all => AxisDateFormat.yearOnly,
              },
              maxLabels: 4,
            ),
            yAxis: metric == PortfolioTrendMetric.marketValue
                ? ValueAxis.currency(
                    currencyCode: series.baseCurrency,
                    maxLabels: 3,
                    showGrid: true,
                  )
                : ValueAxis.percent(
                    fractionDigits: 1,
                    maxLabels: 3,
                    showGrid: true,
                  ),
            filled: true,
            interpolation: ChartInterpolation.linear,
            showDots: false,
            heroDots: true,
            showYAxis: false,
            showTouchXAxisLabel: true,
            semanticLabel: l10n.portfolioTrendChartSemantics,
          ),
        ),
        if (series.hasEstimatedPoints) ...[
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FLucideIcons.info,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  l10n.portfolioTrendEstimatedDisclosure,
                  style: context.microCaptionStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PortfolioTrendMetric extends StatelessWidget {
  const _PortfolioTrendMetric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.microCaptionStyle),
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}

class _PortfolioTrendEmpty extends StatelessWidget {
  const _PortfolioTrendEmpty();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppChartHeights.standard,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.chartNoAxesCombined,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              AppLocalizations.of(context).portfolioTrendAwaitingData,
              textAlign: TextAlign.center,
              style: context.bodyCaptionStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioTrendSkeleton extends StatelessWidget {
  const _PortfolioTrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            SizedBox(width: AppSpacing.s12),
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
            SizedBox(width: AppSpacing.s12),
            Expanded(child: SkeletonBox(height: AppSpacing.s48)),
          ],
        ),
        SizedBox(height: AppSpacing.s16),
        SkeletonBox(height: AppChartHeights.standard),
      ],
    );
  }
}

class _PortfolioTrendError extends StatelessWidget {
  const _PortfolioTrendError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: AppChartHeights.standard,
      child: Center(
        child: FButton(
          variant: FButtonVariant.ghost,
          onPress: onRetry,
          prefix: const Icon(FLucideIcons.refreshCw),
          child: Text(l10n.commonRetry),
        ),
      ),
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
            action: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FButton(
                  onPress: () => showPortfolioLotAssignmentSheet(context),
                  prefix: const Icon(FLucideIcons.briefcaseBusiness),
                  child: Text(l10n.portfolioStudioIncludePositionAction),
                ),
                const SizedBox(height: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => showPortfolioCashAssignmentSheet(context),
                  prefix: const Icon(FLucideIcons.walletCards),
                  child: Text(l10n.portfolioStudioIncludeCashAction),
                ),
              ],
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
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < Breakpoints.formColumn;
            final positions = FButton(
              onPress: () => showPortfolioLotAssignmentSheet(context),
              prefix: const Icon(FLucideIcons.briefcaseBusiness),
              child: Text(l10n.portfolioStudioIncludePositionAction),
            );
            final cash = FButton(
              variant: FButtonVariant.outline,
              onPress: () => showPortfolioCashAssignmentSheet(context),
              prefix: const Icon(FLucideIcons.walletCards),
              child: Text(l10n.portfolioStudioIncludeCashAction),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  positions,
                  const SizedBox(height: AppSpacing.s8),
                  cash,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: positions),
                const SizedBox(width: AppSpacing.s8),
                Expanded(child: cash),
              ],
            );
          },
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
