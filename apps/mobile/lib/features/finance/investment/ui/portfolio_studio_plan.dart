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
    final chart = PortfolioTrendChartProjection.fromSeries(
      series: series,
      metric: PortfolioTrendMetric.performance,
    );
    if (!chart.isRenderable) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          AppLocalizations.of(context).portfolioTrendAwaitingData,
          style: context.microCaptionStyle,
        ),
      );
    }
    final points = [
      for (final datum in chart.data)
        ChartPoint(
          x: datum.asOf.millisecondsSinceEpoch.toDouble(),
          y: datum.value,
          meta: datum.source,
        ),
    ];
    return NwLineChart(
      series: [
        ChartSeries(
          name: AppLocalizations.of(context).portfolioTrendPerformance,
          points: points,
          intent: chart.isDown ? SeriesIntent.down : SeriesIntent.up,
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
